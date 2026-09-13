# Copyright 2026 Trieflow LLC. MIT.
"""Run the exact solution restore options against real NuGet and project-scoped locks."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from xml.sax.saxutils import escape
import zipfile

ROOT=Path(__file__).resolve().parents[2]
DOTNET=os.environ.get('FILEQUAY_DOTNET') or shutil.which('dotnet')

@unittest.skipUnless(DOTNET,'Actual pinned dotnet SDK required')
class RestoreLockScopeTests(unittest.TestCase):
    def test_real_solution_restore_keeps_existing_lock_without_generating_library_lock(self):
        for script in ('qualify-windows.ps1','build-filequay.ps1'):
            with self.subTest(script=script),tempfile.TemporaryDirectory(prefix='foldersail-lock-scope-') as tmp:
                root=Path(tmp);feed=root/'feed';feed.mkdir();packages=root/'packages'
                (root/'global.json').write_bytes((ROOT/'global.json').read_bytes())
                (root/'NuGet.Config').write_text('<configuration><packageSources><clear/><add key="fixture" value="'+escape(str(feed))+'"/></packageSources></configuration>')
                def package(version):
                    with zipfile.ZipFile(feed/('fixture.dependency.'+version+'.nupkg'),'w') as z:
                        z.writestr('fixture.dependency.nuspec','<package><metadata><id>Fixture.Dependency</id><version>'+version+'</version><authors>Fixture</authors><description>Owned restore fixture</description></metadata></package>')
                package('1.0.1')
                # This restore-only fixture has no executable or native crossgen toolchain.
                project='<Project Sdk="Microsoft.NET.Sdk" TreatAsLocalProperty="PublishReadyToRun"><PropertyGroup><PublishReadyToRun>false</PublishReadyToRun><TargetFramework>net10.0</TargetFramework><Platforms>x64</Platforms></PropertyGroup>{}<ItemGroup><PackageReference Include="Fixture.Dependency" Version="1.0.0"/></ItemGroup></Project>'
                # Import the real app's property declaration, while keeping this
                # independent restore fixture's package feed tiny and offline.
                scoped='<Import Project="'+escape(str(ROOT/'distribution/FileQuay.SQLite.props'))+'"/><ItemGroup><PackageReference Remove="Microsoft.Data.Sqlite.Core;SQLitePCLRaw.config.e_sqlite3;SQLite"/><ProjectReference Include="../Library/Library.csproj"/></ItemGroup>'
                for name,imports in [('Application',scoped),('Library','')]:
                    folder=root/name;folder.mkdir();(folder/(name+'.csproj')).write_text(project.format(imports))
                (root/'Files.slnx').write_text('<Solution><Configurations><Platform Name="x64"/></Configurations><Project Path="Application/Application.csproj"/><Project Path="Library/Library.csproj"/></Solution>')
                line=next(v for v in (ROOT/'distribution'/script).read_text().splitlines() if "Invoke-Checked $msbuild @('Files.slnx','-t:Restore'" in v)
                args=re.findall("'([^']*)'",line)
                env=dict(os.environ,DOTNET_CLI_TELEMETRY_OPTOUT='1',NUGET_PACKAGES=str(packages))
                def restore(options):
                    p=subprocess.run([DOTNET,'msbuild',*options,'-p:NuGetAudit=false','-p:RestoreForce=true'],cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=60)
                    self.assertEqual(p.returncode,0,p.stdout[-4000:])
                # Establish an existing application lock from its actual scoped
                # opt-in, before running the production solution restore command.
                restore(['Application/Application.csproj','-t:Restore','-v:quiet'])
                lock=root/'Application/packages.lock.json';original=lock.read_bytes()
                self.assertEqual(json.loads(original)['dependencies']['net10.0']['Fixture.Dependency']['resolved'],'1.0.1')
                package('1.0.0')
                restore(args)
                self.assertFalse((root/'Library/packages.lock.json').exists(),'Production blanket restore generated an unowned library lock file')
                self.assertEqual(lock.read_bytes(),original,'Existing application lock changed despite unchanged references')
                # The lower version is available to the unlocked library, while
                # the application's original closure remains bound to 1.0.1.
                assets=json.loads((root/'Library/obj/project.assets.json').read_text())
                self.assertIn('Fixture.Dependency/1.0.0',assets['libraries'])

if __name__=='__main__':unittest.main()
