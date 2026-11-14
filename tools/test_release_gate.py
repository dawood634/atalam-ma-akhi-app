import copy
import json
from pathlib import Path
import unittest
from catalog_audit import audit, classify
from release_gate import issues, scope_slots, REQUIRED_CHECKS

ROOT = Path(__file__).resolve().parents[1]


class CatalogTests(unittest.TestCase):
    def test_every_real_candidate_is_classified_without_approving_it(self):
        data = json.loads((ROOT / 'content/source_ledger.json').read_text())
        for book in data['books']:
            item = classify(book)
            self.assertNotEqual(item['subject_id'], 'unclassified', book['id'])
            self.assertEqual(item['official_approval_verified'], book['official_approval_verified'])
            self.assertFalse(item['subject_assignment_officially_verified'])
        self.assertEqual(audit(data)['candidate_books'], 136)

    def test_literary_branch_does_not_make_math_or_economics_literature(self):
        for slug, title, expected in [
            ('math-literary-grade-11-yemen', 'كتاب الرياضيات - أدبي', 'mathematics'),
            ('economics-principles-literary-grade-11-yemeni', 'مبادئ علم الاقتصاد - أدبي', 'economics'),
            ('arabic-grade-10-sanaa', 'الأدب والنصوص والبلاغة', 'literature'),
            ('arabic-reading-part-1-grade-11', 'القراءة', 'reading'),
        ]:
            item = classify({'id': slug, 'title': title})
            self.assertEqual(item['subject_id'], expected)
            self.assertFalse(item['branch_assignment_officially_verified'])
        activity = classify({'id':'chemistry-activities-grade-11', 'title':'الأنشطة والتجارب العلمية في الكيمياء'})
        self.assertEqual(activity['branch_hint'], 'unspecified')
        science = classify({'id':'math-grade-12', 'title':'الرياضيات - علمي'})
        self.assertEqual(science['branch_hint'], 'science')

    def test_missing_aden_sources_are_reported_as_gaps(self):
        data = json.loads((ROOT / 'content/source_ledger.json').read_text())
        report = audit(data)
        aden7 = next(s for s in report['grade_track_slots'] if s['track']=='aden' and s['grade']==7)
        self.assertEqual(aden7['track_labeled_candidates'], 0)
        self.assertFalse(aden7['official_required_subjects_confirmed'])


class ReleaseTests(unittest.TestCase):
    def ready_fixture(self):
        # Synthetic validation fixture, never production evidence or curriculum content.
        courses = {}
        matrix = []
        for t,g,b in sorted(scope_slots()):
            key = f'{t}-{g}-{b}'
            courses[key] = {'track':t,'grade':g,'branch':b,'source_book_ids':['source'],
                            'required_lesson_ids':['lesson'], 'lessons':{'lesson':{
                                'status':'approved','independent_reviewer':'test-reviewer',
                                'review_evidence':'https://review.invalid/proof',
                                'source_reference':'https://source.invalid/page'}}}
            matrix.append({'track':t,'grade':g,'branch':b,'official_requirements_verified':True,
                           'official_requirements_reference':'https://source.invalid/plan',
                           'required_courses':[key]})
        checks={n:{'state':'verified','evidence':'synthetic-test-evidence','verified_on':'2026-11-14'} for n in REQUIRED_CHECKS}
        return {'curriculum_matrix':matrix,'courses':courses,'acceptance_checks':checks}, {'books':[{'id':'source','official_approval_verified':True}]}

    def test_real_project_is_not_mistaken_for_a_final_release(self):
        manifest=json.loads((ROOT/'content/release_readiness.json').read_text())
        ledger=json.loads((ROOT/'content/source_ledger.json').read_text())
        self.assertGreater(len(issues(manifest,ledger)),0)
        self.assertEqual(len(manifest['curriculum_matrix']),16)

    def test_complete_schema_fixture_is_accepted(self):
        self.assertEqual(issues(*self.ready_fixture()),[])

    def test_missing_track_branch_and_reviews_block_release(self):
        manifest,ledger=self.ready_fixture()
        manifest['curriculum_matrix'].pop()
        self.assertTrue(issues(manifest,ledger))
        manifest,ledger=self.ready_fixture()
        next(iter(manifest['courses'].values()))['lessons']['lesson']['independent_reviewer']=None
        self.assertTrue(issues(manifest,ledger))
        manifest,ledger=self.ready_fixture()
        ledger['books'][0]['official_approval_verified']=False
        self.assertTrue(issues(manifest,ledger))

    def test_boolean_ready_flag_alone_has_no_effect(self):
        self.assertTrue(issues({'ready':True}, {'books':[]}))

    def test_partial_lesson_coverage_and_unverified_features_block_release(self):
        manifest,ledger=self.ready_fixture()
        course=next(iter(manifest['courses'].values()))
        course['required_lesson_ids'].append('missing')
        self.assertTrue(issues(manifest,ledger))
        manifest,ledger=self.ready_fixture()
        manifest['acceptance_checks']['progress_sync']['state']='pending'
        self.assertTrue(issues(manifest,ledger))


if __name__=='__main__':
    unittest.main()
