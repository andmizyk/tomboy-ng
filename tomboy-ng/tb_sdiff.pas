unit TB_SDiff;
{
    A unit that can display differences between two similar notes.
    User can choose to DoNothing, use First (Remote) or Second (Local)

    // Use Remote, Yellow is mrYes, File1
    // Use Local, Aqua is mrNo, File2
    // Anything else is DoNothing !
}

{ History
    2018/08/14  Added to project
}

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
    ExtCtrls, ComCtrls, kmemo;

type

    { TFormSDiff }

    TFormSDiff = class(TForm)
        Button1: TButton;
        Button2: TButton;
        KMemo1: TKMemo;
        LabelRemote: TLabel;
        LabelLocal: TLabel;
        Label3: TLabel;
        Label4: TLabel;
        Panel1: TPanel;
        RadioShort: TRadioButton;
        RadioLong: TRadioButton;
        procedure FormCreate(Sender: TObject);
        procedure FormShow(Sender: TObject);
        procedure RadioLongChange(Sender: TObject);
    private
        procedure AddDiffText(DiffText : string; NoteNo : integer = 0);
        procedure AddHeader(Title: string);
        {Returns 0 if no further sync works, 1 or 2 depending on which does sync
         eg 1 means you should go incrementing 1 until it looks like 2
         in other words, '1' means 1 can be matched. 2 must have been an insert. }
        function CanResync(const SL1, SL2: TStringList; const Spot1, Spot2, End1, End2: integer
            ): integer;
        procedure CheckFiles();
        procedure GotoEnd(const NoteNo : integer; const SL: TStringList; const Spot, TheEnd: integer);
        function RemoveXml(const St: AnsiString): AnsiString;
        // Returns a new (synced) Pos, showing intermediate lines.
        function Resync(const Target : string; NoteNo : integer; const SL : TStringList; var Spot : integer) : integer;
    public
        RemoteFileName : string;   // #1
        LocalFileName  : string;   // #2
        NoteTitle : string;

    end;

//var
//    FormSDiff: TFormSDiff;

implementation

{$R *.lfm}

uses LazLogger;

{ TFormSDiff }

procedure TFormSDiff.FormCreate(Sender: TObject);
begin

end;


function TFormSDiff.RemoveXml(const St : AnsiString) : AnsiString;
var
    X, Y : integer;
    FoundOne : boolean = false;
begin
    Result := St;
    repeat
        FoundOne := False;
        X := Pos('<', Result);      // don't use UTF8Pos for byte operations
        if X > 0 then begin
            Y := Pos('>', Result);
            if Y > 0 then begin
                Delete(Result, X, Y-X+1);
                FoundOne := True;
            end;
        end;
    until not FoundOne;
    Result := trim(Result);
end;

procedure TFormSDiff.AddDiffText(DiffText : string; NoteNo : integer = 0);
var
    TB, TBPre: TKMemoTextBlock;
begin
    // TB.TextStyle.Font.Size := 16;
    if NoteNo > 0 then begin
        TBpre := KMemo1.Blocks.AddTextBlock(inttostr(NoteNo) + '> ');
        //TBpre.TextStyle.Font.Style := TBpre.TextStyle.Font.Style + [fsBold];
        TBpre.TextStyle.Font.Style := [fsBold];
    end;
    if RadioShort.Checked then
        TB := KMemo1.Blocks.AddTextBlock(Copy(DiffText, 1, 50))
    else TB := KMemo1.Blocks.AddTextBlock(DiffText);
    if NoteNo = 1 then
        TB.TextStyle.Brush.Color := Button1.Color;
    if NoteNo = 2 then
        TB.TextStyle.Brush.Color := Button2.Color;
    KMemo1.blocks.AddParagraph();
end;

procedure TFormSDiff.AddHeader(Title : string);
var
    TB: TKMemoTextBlock;
begin
    KMemo1.Clear(False);
    TB := KMemo1.Blocks.AddTextBlock(Title);
    TB.TextStyle.Font.Size := 16;
    TB.TextStyle.Font.Style := [fsBold];
    KMemo1.blocks.AddParagraph();
end;

function TFormSDiff.CanResync(const SL1, SL2 : TStringList; const Spot1, Spot2, End1, End2 : integer) : integer;
var
    Offset : integer;
begin
    Result := 0;
    for Offset := Spot1 to End1 do
        if RemoveXML(SL1[Offset]) = RemoveXML(SL2[Spot2]) then exit(1);
    for Offset := Spot2 to End2 do
        if RemoveXML(SL2[Offset]) = RemoveXML(SL1[Spot1]) then exit(2);
end;

// Returns a new (synced) Pos, showing intermediate lines.
function TFormSDiff.Resync(const Target : string; NoteNo : integer; const SL : TStringList; var Spot : integer) : integer;
begin
    Result := Spot;
    while RemoveXML(Target) <> RemoveXML(SL[Result]) do begin
        AddDiffText(RemoveXML(SL[Result]), NoteNo);
        inc(Result);
    end;
end;

procedure TFormSDiff.GotoEnd(const NoteNo : integer; const SL : TStringList; const Spot, TheEnd : integer);
var
    I : integer;
begin
    for I := Spot to TheEnd - 1 do
        AddDiffText(RemoveXML(SL[I]), NoteNo);
end;

procedure TFormSDiff.FormShow(Sender: TObject);
begin
    CheckFiles();
end;

procedure TFormSDiff.RadioLongChange(Sender: TObject);
begin
    CheckFiles();
end;

const LinesXML = 16;     // bit arbitary, seems notes have about 16 lines of XML header and footer

procedure TFormSDiff.CheckFiles();
var
    SL1, SL2 : TStringList;
    Pos1, Pos2, Offset1, Offset2, End1, End2 : integer;
    Sync : Integer;
begin
    Pos1 := 0; Pos2 := 0; Offset2 := 0; Offset1 := 0;
    SL1 := TStringList.create;
    SL2 := TStringList.create;
    try
        // open the two files and find their beginnings and ends of content
        SL1.LoadFromFile(RemoteFileName);
        SL2.LoadFromFile(LocalFileName);
        AddHeader(NoteTitle);
        AddDiffText('Remote File 1 ' + inttostr(SL1.Count-LinesXML) + ' lines ' + RemoteFileName, 1);
        AddDiffText('Local File 2 ' + inttostr(SL2.Count-LinesXML) + ' lines ' + LocalFileName, 2);
        while (Pos1 < SL1.Count) and (0 = pos('<note-content version', SL1[Pos1])) do
            inc(Pos1);
        while (Pos2 < SL2.Count) and (0 = pos('<note-content version', SL2[Pos2])) do
            inc(Pos2);
        //if Pos1 = SL1.Count then exit;    // no content found ?
        End1 := Pos1;
        End2 := Pos2;
        while (End1 < SL1.Count) and (0 = pos('</note-content', SL1[End1])) do
            inc(End1);
        while (End2 < SL2.Count) and (0 = pos('</note-content', SL2[End2])) do
            inc(End2);

        while ((Pos1+Offset1 < End1) and (Pos2+Offset2 < End2)) do begin
            if RemoveXML(SL1[Pos1+Offset1]) = RemoveXML(SL2[Pos2+Offset2]) then begin
                inc(Pos1); inc(pos2);
            end else begin
                AddDiffText('---- Out of Sync ----');
                AddDiffText('local ' + RemoveXML(SL2[Pos2+Offset2]), 2);
                AddDiffText('remote ' + RemoveXML(SL1[Pos1+Offset1]), 1);
                inc(Pos1); inc(pos2);
                Sync := CanReSync(SL1, Sl2, Pos1, Pos2, End1, End2);
                case Sync of
                    0:  begin
                            GotoEnd(1, SL1, Pos1, End1);
                            Gotoend(2, SL2, Pos2, End2);
                            break;
                        end;
                    1:  begin
                            Pos1 := Resync(SL2[Pos2], 1, SL1, Pos1);
                        end;
                    2:  begin
                            Pos2 := Resync(SL1[Pos1], 2, SL2, Pos2);
                        end;
                end;
            end;
        end;
    finally
      Sl1.Free;
      Sl2.Free;
    end;
end;

end.

