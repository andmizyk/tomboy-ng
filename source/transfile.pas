unit transfile;

{   Copyright (C) 2017-2020 David Bannon

    License:
    This code is licensed under BSD 3-Clause Clear License, see file License.txt
    or https://spdx.org/licenses/BSD-3-Clause-Clear.html

  ------------------

  A unit that does the file transfer side of a FileSync operation
  HISTORY
  2018/10/25  Much testing, support for Tomdroid.
  2018/06/05  Change to doing Tomboy's sync dir names, rev 431 is in ~/4/341
  2019/10/17  Ensure DownloadFile returns true remote dir name, irrespective of above.
  2021/09/15  Added progress indicator to uploads and downloads
}

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, trans, SyncUtils, tb_utils, ResourceStr;    // we share resources with GithubSync

type

  { TFileSync }

  TFileSync = Class(TTomboyTrans)
    private
        function GetNoteLastChange(const FullFileName: string): string;
            // Reads the (filesync) remote Manifest for synced note details. It gets ID, RevNo
            // and, if its there the LastChangeDate. If LCD is not in manifest and GetLCD
            // is True, gets it from the file.
        function ReadRemoteManifest(const NoteMeta: TNoteInfoList; const GetLCD : boolean): boolean;

    public
        //RemoteDir : string; // where the remote filesync repo lives.
        function SetTransport(): TSyncAvailable; override;
        function TestTransport(const WriteNewServerID : boolean = False) : TSyncAvailable; override;
        function GetRemoteNotes(const NoteMeta : TNoteInfoList; const GetLCD : boolean) : boolean; override;
        function DownloadNotes(const DownLoads : TNoteInfoList) : boolean; override;
        function DeleteNote(const ID : string; const ExistRev : integer) : boolean; override;
        function UploadNotes(const Uploads : TStringList) : boolean; override;
        function DoRemoteManifest(const RemoteManifest : string; MetaData : TNoteInfoList = nil) : boolean; override;
        function DownLoadNote(const ID : string; const RevNo : Integer) : string; Override;
        // function SetRemoteRepo(ManFile : string = '') : boolean; override;
        constructor Create();
  end;


implementation

uses laz2_DOM, laz2_XMLRead, LazFileUtils, FileUtil, LazLogger;

{ TFileSync }

function TFileSync.SetTransport(): TSyncAvailable;
begin
    Result := SyncReady;
end;

function TFileSync.TestTransport(const WriteNewServerID : boolean = False): TSyncAvailable;
var
    Doc : TXMLDocument;
    GUID : TGUID;
    ManExists, ZeroExists : boolean; // for readability of code only
begin
    RemoteAddress := AppendPathDelim(RemoteAddress);
    if not DirectoryExists(RemoteAddress) then
        if not DirectoryExists(RemoteAddress) then begin    // try again because it might be just remounted.
	        ErrorString := 'Remote Dir does not exist ' + #10 + RemoteAddress;
	        exit(SyncNoRemoteDir);
        end;
    if not DirectoryIsWritable(RemoteAddress) then begin
      ErrorString := 'Remote directory NOT writable ' + RemoteAddress;
      exit(SyncNoRemoteWrite);
    end;
    if ANewRepo then begin
        CreateGUID(GUID);
        ServerID := copy(GUIDToString(GUID), 2, 36);      // it arrives here wrapped in {}
        RemoteServerRev := -1;
        exit(SyncReady);
    end;
    ManExists := FileExists(RemoteAddress + 'manifest.xml');
    ZeroExists := DirectoryExists(RemoteAddress + '0');
    if (not ManExists) and (not ZeroExists) then begin
        ErrorString := 'Remote dir does not contain a Repo ' + RemoteAddress;
    	exit(SyncNoRemoteRepo);
	end;
    if (ManExists) and (not ZeroExists) then begin
        ErrorString := 'Apparently damaged repo, missing 0 dir at ' + RemoteAddress;
    	exit(SyncBadRemote);
    end;
	if (not ManExists) and (ZeroExists) then begin
        ErrorString := 'Apparently damaged repo, missing manifest at ' + RemoteAddress;
    	exit(SyncBadRemote);
    end;
    // If to here, looks and feels like a repo, lets see what it can tell !

    try
        try
            ReadXMLFile(Doc, RemoteAddress + 'manifest.xml');
            ServerID := Doc.DocumentElement.GetAttribute('server-id');
            RemoteServerRev := strtoint(Doc.DocumentElement.GetAttribute('revision'));
        except
            on E: EConvertError do begin
                ErrorString := E.Message;
                exit(SyncXMLERROR);	// probably means we did not find an expected attribute
            end;
            on E: EAccessViolation do begin
                ErrorString := E.Message;
                exit(SyncXMLERROR);	// probably means we did not find an expected attribute
            end;
            on E: EFOpenError do begin
                  ErrorString := E.Message;
                  exit(SyncNoRemoteMan);		// File is not present.
            end;
        end;
    finally
        Doc.free;
    end;

(*    try
	        try
	            ReadXMLFile(Doc, RemoteAddress + 'manifest.xml');

	            ServerID := Doc.DocumentElement.GetAttribute('server-id');
                { ToDo : must check for error on next line, it might raise EConvertError }
                RemoteServerRev := strtoint(Doc.DocumentElement.GetAttribute('revision'));
		    finally
	            Doc.Free;
		    end;
	except
      on E: EAccessViolation do begin
          ErrorString := E.Message;
          exit(SyncXMLERROR);	// probably means we did not find an expected attribute
	  end;
	  on E: EFOpenError do begin
            ErrorString := E.Message;
            exit(SyncNoRemoteMan);		// File is not present.
	  end;
	end;      *)

    if 36 <> length(ServerID) then begin
        ErrorString := 'Invalid ServerID';
        exit(SyncXMLError);
    end;
    Result := SyncReady;
end;

function TFileSync.GetRemoteNotes(const NoteMeta: TNoteInfoList; const GetLCD : boolean): boolean;
begin
    if NoteMeta = Nil then begin
        ErrorString := 'Passed an uncreated list to GetNewNotes()';
        exit(False);
    end;
    if FileExists(RemoteAddress + 'manifest.xml') then
        ReadRemoteManifest(NoteMeta, GetLCD);           // No remote manifest is aceptable here, new repo
    result := True;
end;

function TFileSync.ReadRemoteManifest(const NoteMeta: TNoteInfoList; const GetLCD : boolean) : boolean;
var
    Doc : TXMLDocument;
    NodeList : TDOMNodeList;
    Node : TDOMNode;
    j : integer;
    NoteInfo : PNoteInfo;
begin
    Result := true;
    try
    	try
    		ReadXMLFile(Doc, RemoteAddress + 'manifest.xml');
    		NodeList := Doc.DocumentElement.ChildNodes;
    		if assigned(NodeList) then begin
        		for j := 0 to NodeList.Count-1 do begin
                    new(NoteInfo);
                    NoteInfo^.Action:=SyUnset;
                    Node := NodeList.Item[j].Attributes.GetNamedItem('id');
                    NoteInfo^.ID := Node.NodeValue;									// ID does not contain '.note';
					Node := NodeList.Item[j].Attributes.GetNamedItem('rev');
                    NoteInfo^.Rev := strtoint(Node.NodeValue);                      // what happens if its empty ?
                    Node := NodeList.Item[j].Attributes.GetNamedItem('last-change-date');
                    if assigned(node) then
                            NoteInfo^.LastChange:=Node.NodeValue
                    else if GetLCD then begin               // Only bother to get it if we really need it
                        if UsingRightRevisionPath(RemoteAddress, NoteInfo^.Rev) then
                            NoteInfo^.LastChange :=
                                GetNoteLastChange(GetRevisionDirPath(RemoteAddress, NoteInfo^.Rev, NoteInfo^.ID))
                        else
                            NoteInfo^.LastChange := GetNoteLastChange(RemoteAddress
                                    + '0' + pathdelim + inttostr(NoteInfo^.Rev)           // Ugly Hack
                                    + pathdelim + NoteInfo^.ID + '.note');
                    end;
                    if NoteInfo^.LastChange <> '' then
                        NoteInfo^.LastChangeGMT := TB_GetGMTFromStr(NoteInfo^.LastChange);
                    NoteMeta.Add(NoteInfo);
                end;
		end;
		finally
            Doc.Free;
		end;
	except
      on E: EAccessViolation do Result := false;	// probably means we did not find an expected attribute
      on E: EFOpenError do Result := False;		// File is not present.
	end;
    if Result = True then begin
    	if debugmode then Debugln('Transfile.ReadRemoteManifest - read OK');
    end else
        DebugLn('We failed to read the remote manifest file ', RemoteAddress + 'manifest.xml');
end;

function TFileSync.GetNoteLastChange(const FullFileName : string) : string;
begin
    Result := GetNoteLastChangeSt(FullFileName, ErrorString);   // syncutils function
end;

function TFileSync.DownloadNotes(const DownLoads: TNoteInfoList): boolean;
var
    I : integer;
    DLCount : integer = 0;
    FullFileName : string;
    DownCount : integer = 0;
begin
    if ProgressProcedure <> nil then progressProcedure(rsDownloadNotes);
    if not DirectoryExists(NotesDir + 'Backup') then
        if not ForceDirectory(NotesDir + 'Backup') then begin
            ErrorString := 'Failed to create Backup directory.';
            exit(False);
        end;
    for I := 0 to DownLoads.Count-1 do begin
        if DownLoads.Items[I]^.Action = SyDownLoad then begin
            inc(DLCount);
            if (DLCount mod 5 = 0) and (ProgressProcedure <> nil) then
                ProgressProcedure(rsDownLoaded + ' ' + inttostr(DLCount) + ' notes');
            if FileExists(NotesDir + Downloads.Items[I]^.ID + '.note') then
                // First make a Backup copy
                if not CopyFile(NotesDir + Downloads.Items[I]^.ID + '.note',
                        NotesDir + 'Backup' + PathDelim + Downloads.Items[I]^.ID + '.note') then begin
                    ErrorString := 'Failed to copy file to Backup ' + NotesDir + Downloads.Items[I]^.ID + '.note';
                    exit(False);
                end;
            // OK, now copy the file.

            if UsingRightRevisionPath(RemoteAddress, DownLoads.Items[i]^.Rev) then
                FullFilename := GetRevisionDirPath(RemoteAddress, DownLoads.Items[i]^.Rev
                        , Downloads.Items[I]^.ID)
            else
                FullFilename := RemoteAddress + '0' + pathdelim + inttostr(DownLoads.Items[i]^.Rev)   // Ugly Hack
                        + pathdelim + Downloads.Items[I]^.ID + '.note';
            if DebugMode then debugln('Will download ' +  FullFilename);
            if not CopyFile(FullFileName, NotesDir + Downloads.Items[I]^.ID + '.note')
            then begin
                    ErrorString := 'Failed to copy ' + Downloads.Items[I]^.ID + '.note';
                    exit(False);
            end;
            inc(DownCount);
            if (DownCount mod 10 = 0) then
                if ProgressProcedure <> nil then ProgressProcedure(rsDownLoaded + ' ' + inttostr(DownCount) + ' notes');

        end;
    end;
    result := True;
end;

function TFileSync.DeleteNote(const ID: string; const ExistRev : integer ): boolean;
begin
    // I _THINK_ all that happens is deleted note is not listed in remote manifest
    // and that is done. But other thansport modes might need to do something here ?
  result := True;
end;

function TFileSync.UploadNotes(const Uploads: TStringList): boolean;
var
    Index : integer;
    UpCount : integer = 0;
    FullDirName : string;
begin
    if ProgressProcedure <> nil then progressProcedure('Uploading ' + inttostr(UpLoads.Count) + ' notes');
    if UsingRightRevisionPath(RemoteAddress, RemoteServerRev + 1) then
        FullDirName := GetRevisionDirPath(RemoteAddress, RemoteServerRev + 1)
    else
        FullDirName := RemoteAddress + '0' + PathDelim + inttostr(RemoteServerRev + 1) + PathDelim; // Ugly Hack

  for Index := 0 to Uploads.Count -1 do begin
      if DebugMode then debugln(rsUpLoading + ' ' + Uploads.Strings[Index] + '.note');
      if not copyFile(NotesDir + Uploads.Strings[Index] + '.note',
                FullDirname + Uploads.Strings[Index] + '.note')
      then begin
          ErrorString := 'ERROR copying ' + NotesDir + Uploads.Strings[Index] + '.note to '
            + FullDirName + Uploads.Strings[Index] + '.note';
          debugln(ErrorString);
          exit(False);
	  end;
      inc(UpCount);
      if (UpCount mod 5 = 0) and (ProgressProcedure <> nil) then
        progressProcedure(rsUpLoaded + ' ' + inttostr(UpCount) + ' notes');
  end;
  result := True;
end;

function TFileSync.DoRemoteManifest(const RemoteManifest: string; MetaData : TNoteInfoList = nil): boolean;
begin
    if not ForceDirectoriesUTF8(GetRevisionDirPath(RemoteAddress, RemoteServerRev + 1)) then
    begin
        ErrorString := 'Failed to create new remote revision dir '
                + GetRevisionDirPath(RemoteAddress, RemoteServerRev + 1);
        debugln(ErrorString);
        exit(False);
    end;
  if debugmode then  debugln('Remote Manifest is ' + RemoteManifest);
  if not CopyFile(RemoteManifest, RemoteAddress + 'manifest.xml') then begin
      ErrorString := 'Failed to move new root remote manifest file ' + RemoteManifest;
      debugln(ErrorString);
      exit(False);
  end;
  if not CopyFile(RemoteManifest, GetRevisionDirPath(RemoteAddress, RemoteServerRev + 1) + 'manifest.xml') then
  begin
      ErrorString := 'Failed to move new remote manifest file to revision dir';
      debugln(ErrorString);
      exit(False);
  end;
  Result := True;
end;

function TFileSync.DownLoadNote(const ID: string; const RevNo: Integer): string;
begin
    //Result := RemoteAddress + '0' + PathDelim + inttostr(RevNo) + PathDelim + ID + '.note';
    // Due to early bug in -ng, its possible that a file on eg sync rev 393 is in
    // either ~/0/393 or in ~/3/393 - we cannot assume here folks !

    Result := GetRevisionDirPath(RemoteAddress, RevNo, ID);
    if FileExists(Result) then exit;
    Result := RemoteAddress + '0' + PathDelim + inttostr(RevNo) + PathDelim + ID + '.note';
    if not FileExists(Result) then debugln('transfile -> Download() Unable to locate file ' + inttostr(RevNo) + ' ' + ID);
end;

constructor TFileSync.Create();
begin
    ProgressProcedure := nil;
end;

end.

