using System.IO;
using System.Text.Json;
namespace BuddyMovieMaker;
internal sealed class DecoderSettings
{
    readonly string file;
    record Saved(int Version,string DecoderDirectory);
    public DecoderSettings(string? path=null)
    {file=path??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BuddyMovieMaker","settings.json");}
    public (string? Directory,string? Warning) Read()
    {
        try
        {
            if(!File.Exists(file))return(null,null);
            if(new FileInfo(file).Length>8192)throw new InvalidDataException("Settings are too large.");
            var saved=JsonSerializer.Deserialize<Saved>(File.ReadAllText(file));
            if(saved==null || saved.Version!=1 || string.IsNullOrWhiteSpace(saved.DecoderDirectory) || !Path.IsPathFullyQualified(saved.DecoderDirectory) || saved.DecoderDirectory.StartsWith(@"\\"))throw new InvalidDataException("Invalid saved decoder folder.");
            return(saved.DecoderDirectory,null);
        }
        catch(Exception error) when(error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException or ArgumentException or NotSupportedException)
        {return(null,"Saved FFmpeg settings could not be read. Choose existing FFmpeg to select it again.");}
    }
    public string? SaveValidated(string directory)
    {
        string? temporary=null;
        try
        {
            string parent=Path.GetDirectoryName(file)!;Directory.CreateDirectory(parent);
            temporary=Path.Combine(parent,".settings-"+Guid.NewGuid().ToString("N")+".tmp");
            File.WriteAllText(temporary,JsonSerializer.Serialize(new Saved(1,directory)));
            File.Move(temporary,file,true);return null;
        }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {return "FFmpeg is ready for this session, but its location could not be saved. Select it again next time.";}
        finally{if(temporary!=null){try{File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){}}}
    }
}
