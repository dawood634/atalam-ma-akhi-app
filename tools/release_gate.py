"""Fail closed before a final release; never derive readiness from a catalog size."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_CHECKS = ('student_journey', 'teacher_journey', 'teacher_student_link',
                   'offline_curriculum', 'progress_sync', 'grounded_ai',
                   'accessibility', 'privacy', 'android_device_tests',
                   'production_signing', 'content_rights', 'independent_curriculum_review')


def scope_slots():
    return {(t, g, b) for t in ('sanaa', 'aden') for g in range(7, 13)
            for b in (('science', 'literary') if g >= 11 else ('general',))}


def valid_reference(value):
    if not isinstance(value, str):
        return False
    url = urlparse(value)
    return url.scheme == 'https' and bool(url.netloc) and url.netloc not in ('example.com', 'example.org')


def issues(manifest, ledger):
    errors = []
    matrix = manifest.get('curriculum_matrix', [])
    observed = [(m.get('track'), m.get('grade'), m.get('branch')) for m in matrix]
    if len(observed) != len(set(observed)) or set(observed) != scope_slots():
        errors.append('The curriculum matrix must cover all 16 grade/track/branch slots exactly once.')
    books = {b['id']: b for b in ledger['books']}
    courses = manifest.get('courses', {})
    required_courses = set()
    for mapping in matrix:
        key = f"{mapping.get('track')}/{mapping.get('grade')}/{mapping.get('branch')}"
        required = mapping.get('required_courses', [])
        if mapping.get('official_requirements_verified') is not True or not valid_reference(mapping.get('official_requirements_reference')) or not required:
            errors.append(f'{key}: official required subjects and courses are not verified.')
        required_courses.update(required)
        for course_id in required:
            course = courses.get(course_id, {})
            if (course.get('track'), course.get('grade'), course.get('branch')) != (mapping.get('track'), mapping.get('grade'), mapping.get('branch')):
                errors.append(f'{key}: course {course_id} is missing or assigned to a different scope.')
    if not required_courses:
        errors.append('No officially mapped courses exist.')
    for course_id in sorted(required_courses):
        course = courses.get(course_id, {})
        source_ids = course.get('source_book_ids', [])
        if not source_ids or any(books.get(i, {}).get('official_approval_verified') is not True for i in source_ids):
            errors.append(f'{course_id}: official source editions are not verified.')
        expected = course.get('required_lesson_ids', [])
        published = course.get('lessons', {})
        if not expected or len(expected) != len(set(expected)) or set(expected) != set(published):
            errors.append(f'{course_id}: full lesson-by-lesson coverage is not established.')
        for lesson_id in expected:
            lesson = published.get(lesson_id, {})
            if (lesson.get('status') != 'approved' or not lesson.get('independent_reviewer')
                    or not valid_reference(lesson.get('review_evidence'))
                    or not valid_reference(lesson.get('source_reference'))):
                errors.append(f'{course_id}/{lesson_id}: independent review or source traceability is missing.')
    checks = manifest.get('acceptance_checks', {})
    for name in REQUIRED_CHECKS:
        check = checks.get(name, {})
        if check.get('state') != 'verified' or not check.get('evidence') or not check.get('verified_on'):
            errors.append(f'{name}: acceptance evidence is missing.')
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-ready', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'content/release_readiness.json').read_text())
    ledger = json.loads((ROOT / 'content/source_ledger.json').read_text())
    errors = issues(manifest, ledger)
    print(json.dumps({'final_release_ready': not errors, 'blocker_count': len(errors), 'blockers': errors}, ensure_ascii=False, indent=2))
    if args.require_ready and errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
