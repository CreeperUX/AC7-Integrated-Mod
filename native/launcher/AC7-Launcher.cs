// AC7 Integrated.exe (0.7.0, ported from AC8 Integrated 2.5.0): the player tool as its own Windows application. The launcher scripts run inside this
// process (Windows PowerShell 5.1 engine, System.Management.Automation), so the window, the taskbar button, Alt+Tab and
// Task Manager show "AC7 Integrated" with its icon, and pinning works. No console window is ever created.
//   Next to Host.ps1 (the installed app's root): Host.ps1 -Action Gui (checks the installation, then the launcher).
//   Next to Launcher-GUI.ps1 (a portable package or an installed version folder): the launcher directly.
// A splash shows on the main thread while the scripts start on a second STA thread (WPF), until a window appears.
//   --dry-run <file>  write what would run (or "error: ...") to <file> and exit (tests)
//   --smoke <file>    run Launcher-GUI.ps1 -SmokeTest -NoDialog in this process, write "exit=<code>" and the output (tests)
// Built with the .NET Framework 4 compiler included in Windows (native\launcher\build.cmd).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace CreeperUX.AC7Integrated {
 sealed class Plan {
  public string Directory, Script, Error; public bool Host;
  public string Describe(){return Error!=null?"error: "+Error:(Host?"host: ":"launcher: ")+Script+(Host?" -Action Gui":"");}
 }

 static class Program {
  static Exception failure; static int scriptExit; static readonly List<string> output=new List<string>();

  static Plan Resolve(){
   var plan=new Plan();plan.Directory=Path.GetDirectoryName(Application.ExecutablePath);
   string host=Path.Combine(plan.Directory,"Host.ps1"),gui=Path.Combine(plan.Directory,"Launcher-GUI.ps1");
   if(File.Exists(host)){plan.Script=host;plan.Host=true;}
   else if(File.Exists(gui)){plan.Script=gui;}
   else{plan.Error="找不到 Launcher-GUI.ps1。请从完整解压的整合包或安装目录中运行 AC7 Integrated。";}
   return plan;
  }

  // Runs one script in a runspace on the calling (STA) thread; "exit N" in the script ends up in $LASTEXITCODE.
  static void RunScript(string script,IDictionary<string,object> parameters){
   try{
    var state=InitialSessionState.CreateDefault2();
    state.ExecutionPolicy=Microsoft.PowerShell.ExecutionPolicy.Bypass;   // this process only, like powershell.exe -ExecutionPolicy Bypass
    state.ApartmentState=ApartmentState.STA;state.ThreadOptions=PSThreadOptions.UseCurrentThread;
    using(var runspace=RunspaceFactory.CreateRunspace(state)){
     runspace.ApartmentState=ApartmentState.STA;runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;runspace.Open();
     runspace.SessionStateProxy.SetVariable("LASTEXITCODE",0);
     using(var shell=PowerShell.Create()){
      shell.Runspace=runspace;shell.AddCommand(script);
      foreach(var parameter in parameters)shell.AddParameter(parameter.Key,parameter.Value);
      shell.AddCommand("Out-String").AddParameter("Stream",true);
      foreach(var item in shell.Invoke())lock(output)output.Add(item==null?"":item.ToString());
      foreach(var record in shell.Streams.Information)lock(output)output.Add(record.ToString());
      foreach(var record in shell.Streams.Error)lock(output)output.Add("ERROR: "+record);
     }
     var code=runspace.SessionStateProxy.GetVariable("LASTEXITCODE");
     scriptExit=code is int?(int)code:0;
    }
   }catch(Exception e){failure=e;scriptExit=1;}
  }

  [STAThread]
  static int Main(string[] args){
   var plan=Resolve();
   if(args.Length>=2&&args[0]=="--dry-run"){
    File.WriteAllText(args[1],plan.Describe(),new UTF8Encoding(false));
    return plan.Error==null?0:2;
   }
   if(args.Length>=2&&args[0]=="--smoke"){
    var gui=Path.Combine(plan.Directory,"Launcher-GUI.ps1");
    var parameters=new Dictionary<string,object>();parameters["SmokeTest"]=true;parameters["NoDialog"]=true;
    RunOnStaThread(gui,parameters).Join();
    var lines=new List<string>{"exit="+scriptExit};lines.AddRange(output);if(failure!=null)lines.Add("FAILURE: "+failure.Message);
    File.WriteAllLines(args[1],lines.ToArray(),new UTF8Encoding(false));
    return failure==null?scriptExit:1;
   }
   if(plan.Error!=null){ShowError(plan.Error);return 2;}
   var scriptParameters=new Dictionary<string,object>();if(plan.Host)scriptParameters["Action"]="Gui";
   var worker=RunOnStaThread(plan.Script,scriptParameters);
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
   var splash=new Splash(worker);Application.Run(splash);
   worker.Join();
   if(failure!=null&&!splash.WindowSeen)ShowError("启动器没有打开："+failure.Message+"\n\n诊断文件在 diagnostics 文件夹中（安装版在安装目录的 data\\diagnostics）。");
   return scriptExit;
  }

  static Thread RunOnStaThread(string script,IDictionary<string,object> parameters){
   var thread=new Thread(()=>RunScript(script,parameters));thread.SetApartmentState(ApartmentState.STA);thread.IsBackground=false;thread.Start();
   return thread;
  }
  static void ShowError(string text){MessageBox.Show(text,"AC7 Integrated",MessageBoxButtons.OK,MessageBoxIcon.Error);}
 }

 // CreeperUX dark splash: bg #0d1114, text #f4f1eb, muted #a9b0b3, accent #f8b700.
 sealed class Splash : Form {
  readonly Thread worker;readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();readonly DateTime started=DateTime.UtcNow;
  public bool WindowSeen;
  public Splash(Thread worker){
   this.worker=worker;
   FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.CenterScreen;ShowInTaskbar=false;
   BackColor=Color.FromArgb(0x0d,0x11,0x14);Text="AC7 Integrated";AutoScaleMode=AutoScaleMode.Dpi;
   ClientSize=new Size(360,124);DoubleBuffered=true;Cursor=Cursors.AppStarting;
   try{Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);}catch{}
   timer.Interval=100;timer.Tick+=delegate{Check();};timer.Start();
  }
  protected override void OnPaint(PaintEventArgs e){
   float scale=DeviceDpi/96f;var g=e.Graphics;g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
   using(var border=new Pen(Color.FromArgb(0x37,0x37,0x37)))g.DrawRectangle(border,0,0,ClientSize.Width-1,ClientSize.Height-1);
   using(var accent=new SolidBrush(Color.FromArgb(0xf8,0xb7,0x00)))g.FillRectangle(accent,26*scale,30*scale,4*scale,ClientSize.Height-60*scale);
   using(var title=new Font("Segoe UI Semibold",16f))using(var text=new SolidBrush(Color.FromArgb(0xf4,0xf1,0xeb)))g.DrawString("AC7 Integrated",title,text,44*scale,20*scale);
   using(var body=new Font("Microsoft YaHei UI",10f))using(var muted=new SolidBrush(Color.FromArgb(0xa9,0xb0,0xb3)))g.DrawString("正在打开启动器…",body,muted,46*scale,74*scale);
  }
  void Check(){
   if(OwnWindowVisible(Handle)){WindowSeen=true;Finish();}
   else if(!worker.IsAlive||(DateTime.UtcNow-started).TotalSeconds>90)Finish();
  }
  void Finish(){timer.Stop();Close();}

  delegate bool EnumProc(IntPtr window,IntPtr data);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr data);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
  // A visible top-level window of this process other than the splash: the launcher, or the message it shows.
  static bool OwnWindowVisible(IntPtr splash){
   uint self=(uint)System.Diagnostics.Process.GetCurrentProcess().Id;IntPtr found=IntPtr.Zero;
   EnumWindows((window,data)=>{
    uint pid;GetWindowThreadProcessId(window,out pid);
    if(pid==self&&window!=splash&&IsWindowVisible(window)){found=window;return false;}
    return true;
   },IntPtr.Zero);
   if(found!=IntPtr.Zero)SetForegroundWindow(found);
   return found!=IntPtr.Zero;
  }
 }
}
