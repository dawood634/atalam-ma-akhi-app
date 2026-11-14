"""Classify candidate titles and report gaps without approving curricula."""
import argparse
import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Stable catalog identifiers, not inferred official subject assignments.
SUBJECTS = [
    (('hadith-fiqh',), 'hadith_fiqh', 'الحديث والفقه'),
    (('quran',), 'quran', 'القرآن الكريم وعلومه'),
    (('islamic',), 'islamic', 'التربية الإسلامية'),
    (('iman', 'faith'), 'faith', 'الإيمان'),
    (('hadith',), 'hadith', 'الحديث والتهذيب'),
    (('fiqh',), 'fiqh', 'الفقه'),
    (('sira', 'seerah'), 'seerah', 'السيرة النبوية'),
    (('grammar', 'arabic-grammar'), 'grammar', 'النحو والصرف'),
    (('reading', 'arabic-reading'), 'reading', 'القراءة'),
    (('literature',), 'literature', 'الأدب والنصوص'),
    (('arabic',), 'arabic', 'اللغة العربية'),
    (('mathematics', 'math'), 'mathematics', 'الرياضيات'),
    (('science', 'sciences'), 'science', 'العلوم'),
    (('biology',), 'biology', 'الأحياء'),
    (('physics',), 'physics', 'الفيزياء'),
    (('chemistry', 'activities-chemistry'), 'chemistry', 'الكيمياء'),
    (('english',), 'english', 'اللغة الإنجليزية'),
    (('civics', 'civic'), 'civics', 'التربية الوطنية'),
    (('geography',), 'geography', 'الجغرافيا'),
    (('history', 'tarikh'), 'history', 'التاريخ'),
    (('yemen-society',), 'yemen_society', 'المجتمع اليمني'),
    (('economics',), 'economics', 'مبادئ علم الاقتصاد'),
    (('sociology',), 'sociology', 'علم الاجتماع'),
    (('psychology',), 'psychology', 'علم النفس'),
    (('philosophy',), 'philosophy', 'مبادئ الفلسفة'),
    (('logic',), 'logic', 'المنطق ومناهج البحث العلمي'),
    (('cartography',), 'cartography', 'مبادئ علم الخرائط'),
    (('computer',), 'computer', 'الحاسوب'),
]


def classify(book):
    result = dict(book)
    slug, title = book['id'], book['title']
    # Arabic secondary literature books use the broad `arabic` catalog slug.
    if 'الأدب' in title or 'الادب' in title:
        subject_id, label = 'literature', 'الأدب والنصوص'
    else:
        subject_id, label = 'unclassified', 'غير محدد'
        for prefixes, key, name in SUBJECTS:
            if any(slug == prefix or slug.startswith(prefix + '-') for prefix in prefixes):
                subject_id, label = key, name
                break
    result.update(subject_id=subject_id, subject_label=label,
                  subject_classification_basis='catalog_identifier_and_title',
                  subject_assignment_officially_verified=False,
                  branch_hint='literary' if 'أدبي' in title else 'science' if 'علمي' in title else 'unspecified',
                  branch_hint_basis='explicit_listing_title' if ('أدبي' in title or 'علمي' in title) else 'not_stated',
                  branch_assignment_officially_verified=False)
    return result


def audit(ledger):
    books = ledger['books']
    assert len({b['id'] for b in books}) == len(books), 'Duplicate book identifiers'
    slots = []
    for track in ('sanaa', 'aden'):
        for grade in range(7, 13):
            exact = [b for b in books if b['grade'] == grade and b['claimed_track'] == track]
            common = [b for b in books if b['grade'] == grade and b['claimed_track'] == 'common']
            slots.append({'track': track, 'grade': grade,
                          'track_labeled_candidates': len(exact),
                          'catalog_common_candidates': len(common),
                          'candidate_subjects': sorted({b['subject_label'] for b in exact + common}),
                          'official_required_subjects_confirmed': False,
                          'official_approved_books': sum(b['official_approval_verified'] is True for b in exact + common),
                          'fully_verified_coverage_books': sum(b['coverage_verified'] is True for b in exact + common),
                          'gap': 'no_track_labeled_candidates' if not exact else 'official_editions_and_lesson_coverage_unconfirmed'})
    return {'schema_version': 1, 'inventory_kind': 'candidate_catalog_not_curriculum_requirements',
            'candidate_books': len(books),
            'classified_candidate_books': sum(b.get('subject_id', 'unclassified') != 'unclassified' for b in books),
            'subject_counts': dict(sorted(collections.Counter(b['subject_label'] for b in books).items())),
            'official_approved_books': sum(b['official_approval_verified'] is True for b in books),
            'fully_verified_coverage_books': sum(b['coverage_verified'] is True for b in books),
            'grade_track_slots': slots}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'content/source_ledger.json'
    ledger = json.loads(path.read_text())
    if args.write:
        ledger['books'] = [classify(b) for b in ledger['books']]
        ledger['schema_version'] = 2
        path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + '\n')
    result = audit(ledger)
    if args.write:
        (ROOT / 'content/coverage_audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
