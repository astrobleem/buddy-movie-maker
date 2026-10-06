using System.Windows;
namespace BuddyMovieMaker;
public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if(e.Args.Length>0 && e.Args[0]=="--self-test-decoder-settings")
        {
            ShutdownMode=ShutdownMode.OnExplicitShutdown;
            try{if(e.Args.Length!=5)throw new ArgumentException("Settings test requires mode, isolated settings file, report and decoder folder.");await SelfTest.DecoderSettingsProcess(e.Args[1],e.Args[2],e.Args[3],e.Args[4]);Shutdown(0);}
            catch(Exception error){if(e.Args.Length>=4)System.IO.File.WriteAllText(e.Args[3],error.ToString());Shutdown(1);}
            return;
        }
        if(e.Args.Length>0 && e.Args[0]=="--self-test")
        {
            ShutdownMode=ShutdownMode.OnExplicitShutdown;
            try {
                if(e.Args.Length<3)throw new ArgumentException("Self-test requires output directory and existing decoder directory.");
                await MovieEngine.CheckDecoder(e.Args[2],CancellationToken.None);
                await Task.Run(()=>SelfTest.Run(e.Args[1]));Shutdown(0);
            }
            catch(Exception error){System.IO.File.WriteAllText(System.IO.Path.Combine(AppContext.BaseDirectory,"self-test-error.txt"),error.ToString());Shutdown(1);}
            return;
        }
        new MainWindow().Show();
    }
}
