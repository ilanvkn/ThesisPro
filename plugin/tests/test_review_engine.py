import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'scripts' / 'review_engine.py'
spec = importlib.util.spec_from_file_location('review_engine', path)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class ReviewEngineTests(unittest.TestCase):
    def setUp(self):
        self.project = {'title': 'Example research', 'chapters': [], 'sources': [{'id': 's1'}], 'claims': [], 'research_design': {}}
        self.review_id = engine.start(self.project, 'A bounded claim', 'fixture-time')['review']['id']

    def report(self, decision='support_within_scope'):
        return {'summary': 'Fixture review, not a real research result', 'findings': [
            {'claim': 'A fixture claim', 'decision': decision, 'evidence': 'Fixture source, page 1', 'limitations': 'No real-world inference', 'source_ids': ['s1']}]}

    def test_all_roles_do_not_confer_academic_approval(self):
        for role in engine.ROLES:
            engine.record(self.project, self.review_id, role, self.report(), 't')
        result = engine.status(self.project, self.review_id)
        self.assertEqual(result['roles_recorded'], 6)
        self.assertEqual(result['missing_roles'], [])
        self.assertFalse(result['academic_approval'])

    def test_research_changes_reject_stale_reports(self):
        self.project['sources'][0]['citation'] = 'Corrected source'
        self.assertTrue(engine.status(self.project, self.review_id)['stale'])
        with self.assertRaises(ValueError):
            engine.record(self.project, self.review_id, 'evidence', self.report(), 't')
        self.assertEqual(engine.status(self.project, self.review_id)['roles_recorded'], 0)

    def test_disagreements_and_prior_reports_survive(self):
        engine.record(self.project, self.review_id, 'critic', self.report('revise'), 't')
        engine.record(self.project, self.review_id, 'evidence', self.report(), 't')
        self.assertEqual(len(engine.status(self.project, self.review_id)['unresolved_findings']), 1)
        engine.record(self.project, self.review_id, 'critic', self.report('insufficient_evidence'), 't2')
        review = engine.status(self.project, self.review_id)['review']
        self.assertEqual(review['history'][0]['previous']['findings'][0]['decision'], 'revise')

    def test_unknown_sources_and_approval_labels_rejected(self):
        report = self.report(); report['findings'][0]['source_ids'] = ['invented']
        with self.assertRaises(ValueError):engine.record(self.project, self.review_id, 'evidence', report, 't')
        with self.assertRaises(ValueError):engine.record(self.project, self.review_id, 'evidence', self.report('approved'), 't')
        with self.assertRaises(ValueError):engine.record(self.project, self.review_id, 'famous professor', self.report(), 't')
        with self.assertRaises(ValueError):engine.record(self.project, self.review_id, 'editor', {'summary': 'Done', 'findings': []}, 't')
