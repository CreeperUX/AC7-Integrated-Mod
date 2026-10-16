"""Write LauncherVersion.cs (title, company and version of AC7 Integrated.exe) from package/package-info.json."""
from pathlib import Path
import json,re,sys
version=json.loads((Path(__file__).resolve().parents[2]/'package'/'package-info.json').read_text(encoding='utf-8-sig'))['version']
number='.'.join(re.match(r'^(\d+)\.(\d+)\.(\d+)',version).groups())
Path(sys.argv[1]).write_text('\n'.join([
 'using System.Reflection;',
 '[assembly: AssemblyTitle("AC7 Integrated")]',
 '[assembly: AssemblyDescription("AC7 Integrated player tool")]',
 '[assembly: AssemblyCompany("CreeperUX")]',
 '[assembly: AssemblyProduct("AC7 Integrated")]',
 f'[assembly: AssemblyVersion("{number}.0")]',
 f'[assembly: AssemblyFileVersion("{number}")]',
 f'[assembly: AssemblyInformationalVersion("{version}")]',''
]),encoding='utf-8')
