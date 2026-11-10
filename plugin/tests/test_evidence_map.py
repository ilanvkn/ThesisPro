import importlib.util
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from evidence_map import extract,reconcile

class EvidenceMapTests(unittest.TestCase):
    def project(self):
        return {'id':'example','chapters':[{'number':1,'title':'Introduction','sections':{'a':{'content':'1.1 Purpose\n\n'+'An explicit research proposal. '*8}}}]}
    def test_preserves_exact_notes_and_archives_changed_passage(self):
        p=self.project();p['academic_journey']=extract(p);p['academic_journey'][0]['evidence']='Source page 4'
        current,old=reconcile(p);self.assertEqual(current[0]['evidence'],'Source page 4');self.assertEqual(old,[])
        p['chapters'][0]['sections']['a']['content']+=' Changed.'
        current,old=reconcile(p);self.assertEqual(current[0]['evidence'],'');self.assertEqual(old[0]['evidence'],'Source page 4')
    def test_idempotent_and_no_cross_project_notes(self):
        p=self.project();p['academic_journey']=extract(p);p['academic_journey'][0]['evidence']='Private'
        p['id']='different';current,old=reconcile(p);self.assertEqual(current[0]['evidence'],'')
        p['academic_journey']=current;self.assertEqual(reconcile(p),(current,[]))
    def test_references_excluded(self):
        p=self.project();p['chapters'][0]['title']='Rujukan';self.assertEqual(extract(p),[])
