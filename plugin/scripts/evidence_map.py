"""Literal manuscript reconciliation. Source links never confer claim approval."""
import copy
import hashlib
import re


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def chapter_text(chapter):
    sections = chapter.get('sections', {})
    def order(key):
        return (0 if key == 'Mac application draft' else 1 if key == 'Recovered working draft' else 2, key)
    return '\n\n'.join(sections[k].get('content', '') for k in sorted(sections, key=order))


def extract(project):
    links = []
    for index, chapter in enumerate(project['chapters']):
        title = chapter['title']
        if any(term in title.casefold() for term in ('references', 'bibliography', 'rujukan')):
            continue
        if not title.startswith('Chapter '):
            title = f"Chapter {chapter['number']}: {title}"
        heading, needs_passage = title, True
        for raw in chapter_text(chapter).split('\n\n'):
            block = raw.strip()
            if block.startswith('#') or (len(block) < 200 and '\n' not in block and re.match(r'^\d+\.\d+(?:\.\d+)*\s', block)):
                heading, needs_passage = block.strip('# '), True
            elif needs_passage and len(block) > 100 and not block.startswith(('|', '![')):
                links.append(dict(id=digest(f"{project['id']}|{index}|{heading}|{block}"), chapterIndex=index,
                                  chapterTitle=title, concept=heading, passage=block, evidence='', decision='',
                                  limitation='', reviewNotes='', priority=False, evidenceStatus='needs_review'))
                needs_passage = False
    return links


def reconcile(project):
    """Only exact identities inherit notes; changed notes remain in history."""
    old = {item['id']: item for item in project.get('academic_journey', [])}
    result = []
    for item in extract(project):
        prior = old.get(item['id'])
        if prior and prior.get('passage') == item['passage'] and prior.get('concept') == item['concept']:
            item = copy.deepcopy(prior)
        result.append(item)
    current_ids = {item['id'] for item in result}
    archived = [copy.deepcopy(item) for key, item in old.items() if key not in current_ids]
    return result, archived
