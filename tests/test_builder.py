import pathlib, re, unittest, zipfile

ROOT=pathlib.Path(__file__).resolve().parents[1]
class BuilderTests(unittest.TestCase):
    def test_workflow(self):
        s=(ROOT/'.github/workflows/build-fileoptimizer-portable.yml').read_text(encoding='utf-8')
        self.assertIn('workflow_dispatch:',s)
        self.assertIn('actions/upload-artifact@v6',s)
        self.assertIn('windows-2022',s)
        self.assertNotIn('schedule:',s)
    def test_official_url_and_checksum(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('downloads.sourceforge.net/project/nikkhokkho/FileOptimizer/',s)
        self.assertIn('FileOptimizerFull.7z.exe',s)
        self.assertIn('9f0a3aef27adece2ab3cedbb004c084ad9e1a36f79155dd3e0e2d7fc0182fb72',s)
        self.assertIn('Get-FileHash -Algorithm SHA256',s)
    def test_no_vendor_installer_executed(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('& $seven x',s)
        self.assertNotIn('FileOptimizerSetup.exe',s)
    def test_required_plugins_not_lost(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('Plugins64',s)
        self.assertIn('Get-ChildItem -LiteralPath $programRoot -Force',s)
    def test_own_settings(self):
        s=(ROOT/'launcher/FileOptimizerPortable.cs').read_text(encoding='utf-8')
        for x in ('Data','Settings','Logs','TEMP','TMP','FileOptimizer64.exe','Mutex','--self-test'):
            self.assertIn(x,s)
        self.assertNotIn('RegistryKey.Delete',s)
    def test_appinfo_location(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('App/AppInfo',s)
        self.assertIn('Start=FileOptimizerPortable.exe',s)
        self.assertIn('appicon.ico',s)
    def test_parent_folder(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('FileOptimizerPortable/FileOptimizerPortable.exe',s)
        self.assertIn('CreateFromDirectory($packRoot',s)
    def test_local_unicode_reading(self):
        for p in (ROOT/'README.md', ROOT/'docs/TESTING.md'):
            self.assertTrue(p.read_text(encoding='utf-8'))
    def test_blocked_checksum_page_does_not_always_fail(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn('OFFICIAL-HTTPS-UNPINNED',s)
        self.assertIn('NOT independently verified',s)
        self.assertIn('7z archive-integrity test',s)
        self.assertNotIn('No published SourceForge SHA256 could be verified',s)
    def test_manual_checksum_is_verified(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        workflow=(ROOT/'.github/workflows/build-fileoptimizer-portable.yml').read_text(encoding='utf-8')
        self.assertIn('ExpectedSha256',s)
        self.assertIn("$actual -ne $expected",s)
        self.assertIn('expected_sha256:',workflow)
        self.assertIn('SHA256_INPUT',workflow)
    def test_download_sources_are_official(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf-8')
        self.assertIn("$sourcePage + '?use_mirror=pilotfiber'",s)
        self.assertIn('https://sourceforge.net/projects/nikkhokkho/files/FileOptimizer/',s)
    def test_node24_actions(self):
        s=(ROOT/'.github/workflows/build-fileoptimizer-portable.yml').read_text(encoding='utf-8')
        self.assertIn('actions/checkout@v6',s)
        self.assertIn('actions/upload-artifact@v6',s)
if __name__=='__main__': unittest.main()
