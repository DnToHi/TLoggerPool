unit AsyncLoggerPool;
//=======================================================================
//    �첽��־����־���� (TAnsycLogger & TLoggerPool) ver.1.0
//    DnToHi  ( DnToHi#gmail.com)
//    2025/10/08
//    ��־����Լ�� ( LogLevel ) ��
//          0 - DetailDebug
//          1 - Debug
//          2 - Info
//          3 - Warning
//          4 - Error
//          5 - Fatal
//          6 - Unknown ( Unset )
//=======================================================================

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.SyncObjs, System.DateUtils, System.IOUtils,
  Winapi.Windows;

const
  WRITE_LOG_DIR                 = 'Log';                    // ��־�ļ�Ĭ��Ŀ¼
  LOG_ERROR_SUCCESS             = 1;
  LOG_ERROR_LOGGERPOOL_NOT_INIT = -1;
  LOG_ERROR_IS_UNCPATH          = -11;
  LOG_ERROR_IS_DRIVEROOT_PATH   = -12;

type
  TLogRootPathType = (lrpAppPath { lrpModulePath, default }, lrpDocumentsPath, lrpCachePath, lrpHomePath);
  TLogLevel = (llDetailDebug, llDebug, llInfo, llWarning, llError, llFatal, llUnknown);

const
  {$WRITEABLECONST ON}
  WRITE_LOG_MIN_LEVEL: Byte = Ord(llDetailDebug);             // д��־����ͼ���С�ڴ˼��𲻼�¼��Ĭ�� llDetailDebug
  WRITE_LOG_TIME_FORMAT: string = 'yyyy-mm-dd hh:nn:ss.zzz';  // д��־���ʱ��ĸ�ʽ
  LOG_FILE_MAX_SIZE_IN_BYTE: NativeInt = 20 * 1024 * 1024;    // ��־�ļ�����С���ֽڣ���Ĭ�� 20M
  MAX_QUEUE_ITEMS: NativeInt = 20000;                         // ��־��Ŀ�б��������������ʱ�����������־��Ŀ
  MIN_CLEANUP_DAYS: NativeInt = 31;                           // ��־�ļ�Ŀ¼�����洢���������־������ʱ�ƶ��� backup ��Ŀ¼��
  WRITER_THREAD_INTERVAL: Cardinal = 100;                     // д��־�߳���ѯʱ���������룩
  {$WRITEABLECONST OFF}

type
  TAsyncLogger = class
  private
    // ��־��Ŀ
    type
      TLogItem = record
        Bytes: TBytes;
        Level: TLogLevel;
      end;
  private
    FQueue: TQueue<TLogItem>;                               // ��д����־��Ŀ�б�
    FQueueLock: TRTLSRWLock;                                // ��־��Ŀ�б������

    FWriterThread: TThread;                                 // ����־��Ŀд������ļ����߳�
    FNewItemEvent: TEvent;                                  // ���µ���־��Ŀ
    FTerminate: Boolean;                                    // �Ƿ�Ҫ�˳�

    FFileStream: TFileStream;                               // �ļ���������д�߳��в���
    FCurrentLogFileName: string;                            // ��ǰ��־�ļ�����
    FCurrentLogTime: TDateTime;                             // ��ǰ��־�ļ�����ʱ��
//    FLastCleanupTime: TDateTime;                            // �ϴ��������־�ļ���ʱ��

    FPrevSendLog: string;                                   // ��һ�η�����־�����ݣ��������ַ��ͽ���ʱΪ��һ�ε���־����
    FPrevSendLogLevel: TLogLevel;                           // ��һ�η�����־�ĵȼ����������ַ��ͽ���ʱΪ��һ�ε���־�ȼ�
    FPrevRecvLog: string;                                   // ��һ�ν�����־������
    FPrevRecvLogLevel: TLogLevel;                           // ��һ�ν�����־�ĵȼ�

    FLoggerName: string;                                    // ��־���������
    FLogFilePath: string;                                   // ��־�ļ�����Ŀ¼
    FLogFileNamePrefix: string;                             // ��־�ļ���ǰ׺

    FFilterLog: Boolean;                                    // �Ƿ������־����
    FDistinguishSendRecv: Boolean;                          // ��־�Ƿ����ַ��ͺͽ���
    FSendPrefix: string;                                    // ������־��ǰ׺
    FRecvPrefix: string;                                    // ������־��ǰ׺

    function GetLogFileNameForNow: string;
    procedure EnsureLogDirExists;
    procedure WriterThreadProc;                             // thread proc
    procedure CreateNewStream(const AFileName: string);
    procedure CloseStreamSafe;
    procedure RotateBySizeIfNeeded;
    procedure RotateByDateIfNeeded;
    function MakeBackupName(const AFileName: string): string;
    procedure CleanupOldLogs;
  public
    constructor Create(const ALoggerName, ALogFilePath, ALogFileNamePrefix: string;
      AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string);
    destructor Destroy; override;

    procedure Log(const AText: string; ALogLevel: TLogLevel);
    procedure LogFmt(const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel);

    procedure Flush;                                        // ��ѡ���̣�ǿ�ƻ���д��־�̣߳�����δд����̵���־��Ŀд�����

    property LoggerName: string read FLoggerName;
  end;

  TLoggerPool = class
  private
    FLoggers: TObjectDictionary<string, TAsyncLogger>;
    FLock: TRTLCriticalSection;
    FBasePath: string;
  public
    constructor Create(const ABasePath: string);
    destructor Destroy; override;

    function GetLogger(const ALoggerName, ALogFilePath, ALogFileNamePrefix: string;
      AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): TAsyncLogger;

    procedure FlushAll;
    procedure ShutdownAll;
  end;

  function CreateGlobalLogger(ALogRootPathType: TLogRootPathType;
    const ALoggerName, ALogPath, ALogFileNamePrefix: string;
    AFilterLog: Boolean = True; ADistinguishSendRecv: Boolean = True; const ASendPrefix: string = '';
    const ARecvPrefix: string = ''): NativeInt;
  procedure FreeGlobalLogger;
  procedure WriteLog(const AText: string; ALogLevel: TLogLevel = llDetailDebug); overload;
  procedure WriteLogFmt(const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel = llDetailDebug); overload;

  function CreateGlobalLoggerPool(ALogRootPathType: TLogRootPathType): NativeInt;
  procedure FreeGlobalLoggerPool;
  function GetLogger(out ALogger: TAsyncLogger; const ALoggerName, ALogPath, ALogFileNamePrefix: string;
    AFilterLog: Boolean = True; ADistinguishSendRecv: Boolean = True; const ASendPrefix: string = '';
    const ARecvPrefix: string = ''): NativeInt;
  procedure WriteLog(ALogger: TAsyncLogger; const AText: string; ALogLevel: TLogLevel = llDetailDebug); overload;
  procedure WriteLogFmt(ALogger: TAsyncLogger; const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel = llDetailDebug); overload;

var
  GlobalLogger: TAsyncLogger = nil;
  GlobalLoggerPool: TLoggerPool = nil;

implementation


{ ----------------- Global helpers ----------------- }

function CreateGlobalLoggerPool(ALogRootPathType: TLogRootPathType): NativeInt;
var
  LLogPath: string;
begin
  if Assigned(GlobalLoggerPool) then
    Exit(LOG_ERROR_SUCCESS);

  case ALogRootPathType of
    lrpDocumentsPath: LLogPath := TPath.Combine(TPath.GetDocumentsPath, 'DnToHi');
    lrpCachePath: LLogPath := TPath.Combine(TPath.GetCachePath, 'DnToHi');
    lrpHomePath: LLogPath := TPath.Combine(TPath.GetHomePath, 'DnToHi');
    else begin
      if IsLibrary then
        LLogPath := ExtractFilePath(System.SysUtils.GetModuleName(HInstance))
      else
        LLogPath := ExtractFilePath(ParamStr(0));
    end;
  end;
  GlobalLoggerPool := TLoggerPool.Create(LLogPath);
  Result := LOG_ERROR_SUCCESS;
end;

procedure FreeGlobalLoggerPool;
begin
  FreeAndNil(GlobalLoggerPool);
end;

function GetLogger(out ALogger: TAsyncLogger;const ALoggerName, ALogPath, ALogFileNamePrefix: string;
  AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): NativeInt;
var
  LLogPath: string;
begin
  ALogger := nil;
  if not Assigned(GlobalLoggerPool) then
    Exit(LOG_ERROR_LOGGERPOOL_NOT_INIT);

  if TPath.IsUNCPath(ALogPath) then
    Exit(LOG_ERROR_IS_UNCPATH);

  if TPath.IsDriveRooted(ALogPath) then
    Exit(LOG_ERROR_IS_DRIVEROOT_PATH);

  if ALogPath = '' then
    LLogPath := TPath.Combine(GlobalLoggerPool.FBasePath, WRITE_LOG_DIR)
  else
    LLogPath := TPath.Combine(GlobalLoggerPool.FBasePath, ALogPath);

  ALogger := GlobalLoggerPool.GetLogger(ALoggerName, LLogPath, ALogFileNamePrefix, AFilterLog,
    ADistinguishSendRecv, ASendPrefix, ARecvPrefix);
  Result := LOG_ERROR_SUCCESS;
end;

procedure WriteLog(ALogger: TAsyncLogger; const AText: string; ALogLevel: TLogLevel);
begin
  if Assigned(ALogger) then
  begin
    try
      ALogger.Log(AText, ALogLevel);
    except
    end;
  end;
end;

procedure WriteLogFmt(ALogger: TAsyncLogger; const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel);
begin
  if Assigned(ALogger) then
  begin
    try
      ALogger.LogFmt(AFormat, AArgs, ALogLevel);
    except
    end;
  end;
end;

function CreateGlobalLogger(ALogRootPathType: TLogRootPathType;
  const ALoggerName, ALogPath, ALogFileNamePrefix: string; AFilterLog,
  ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): NativeInt;
var
  LLogPath: string;
begin
  if Assigned(GlobalLogger) then
    Exit(LOG_ERROR_SUCCESS);

  if TPath.IsUNCPath(ALogPath) then
    Exit(LOG_ERROR_IS_UNCPATH);

  if TPath.IsDriveRooted(ALogPath) then
    Exit(LOG_ERROR_IS_DRIVEROOT_PATH);

  case ALogRootPathType of
    lrpDocumentsPath: LLogPath := TPath.Combine(TPath.GetDocumentsPath, 'DnToHi');
    lrpCachePath: LLogPath := TPath.Combine(TPath.GetCachePath, 'DnToHi');
    lrpHomePath: LLogPath := TPath.Combine(TPath.GetHomePath, 'DnToHi');
    else begin
      if IsLibrary then
        LLogPath := ExtractFilePath(System.SysUtils.GetModuleName(HInstance))
      else
        LLogPath := ExtractFilePath(ParamStr(0));
    end;
  end;
  if ALogPath = '' then
    LLogPath := TPath.Combine(LLogPath, WRITE_LOG_DIR)
  else
    LLogPath := TPath.Combine(LLogPath, ALogPath);
  GlobalLogger := TAsyncLogger.Create(ALoggerName, LLogPath, ALogFileNamePrefix, AFilterLog, ADistinguishSendRecv,
    ASendPrefix, ARecvPrefix);
  Result := LOG_ERROR_SUCCESS;
end;

procedure FreeGlobalLogger;
begin
  FreeAndNil(GlobalLogger);
end;

procedure WriteLog(const AText: string; ALogLevel: TLogLevel);
var
  L: TAsyncLogger;
begin
  L := GlobalLogger; // local ref
  if Assigned(L) then
  begin
    try
      L.Log(AText, ALogLevel);
    except
      // swallow to avoid bubbling
    end;
  end;
end;

procedure WriteLogFmt(const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel);
var
  L: TAsyncLogger;
begin
  L := GlobalLogger;
  if Assigned(L) then
  begin
    try
      L.LogFmt(AFormat, AArgs, ALogLevel);
    except
      // swallow
    end;
  end;
end;

{ TAsyncLogger }

constructor TAsyncLogger.Create(const ALoggerName, ALogFilePath, ALogFileNamePrefix: string;
  AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string);
begin
  inherited Create;
  FLoggerName := ALoggerName;
  FLogFilePath := ALogFilePath;
  FLogFileNamePrefix := ALogFileNamePrefix;

  FFilterLog := AFilterLog;
  FDistinguishSendRecv := ADistinguishSendRecv;
  FSendPrefix := ASendPrefix;
  FRecvPrefix := ARecvPrefix;

  FQueue := TQueue<TLogItem>.Create;
  InitializeSRWLock(FQueueLock);

  FNewItemEvent := TEvent.Create(nil, False, False, '');
  FTerminate := False;

  FFileStream := nil; // delayed creation, it will be created when it is used the first time

  FCurrentLogFileName := '';
  FCurrentLogTime := 0;
//  FLastCleanupTime := 0;

  FPrevSendLog := '';
  FPrevSendLogLevel := llUnknown;
  FPrevRecvLog := '';
  FPrevRecvLogLevel := llUnknown;

  FWriterThread := TThread.CreateAnonymousThread(WriterThreadProc);
  FWriterThread.FreeOnTerminate := False;
  FWriterThread.Start;
end;

destructor TAsyncLogger.Destroy;
begin
  FTerminate := True;
  if Assigned(FNewItemEvent) then
    FNewItemEvent.SetEvent;

  if Assigned(FWriterThread) then
  begin
    FWriterThread.WaitFor;
    FreeAndNil(FWriterThread);
  end;

  AcquireSRWLockExclusive(FQueueLock);
  try
    FQueue.Clear;
  finally
    ReleaseSRWLockExclusive(FQueueLock);
  end;

  FreeAndNil(FQueue);

  if Assigned(FNewItemEvent) then
    FreeAndNil(FNewItemEvent);
  CloseStreamSafe;
  inherited;
end;

procedure TAsyncLogger.EnsureLogDirExists;
begin
  if not TDirectory.Exists(FLogFilePath) then
  begin
    try
      ForceDirectories(FLogFilePath);
    except
      // ignore; writer will try to open and fallback to debug output on failure
    end;
  end;
end;

function TAsyncLogger.GetLogFileNameForNow: string;
begin
  FCurrentLogTime := Now;
  Result := TPath.Combine(FLogFilePath, FLogFileNamePrefix + '_' + FormatDateTime('yyyymmdd', FCurrentLogTime) + '.log');
end;

procedure TAsyncLogger.CreateNewStream(const AFileName: string);
var
  Mode: Word;
begin
  CloseStreamSafe;
  EnsureLogDirExists;
  try
    if TFile.Exists(AFileName) then
      Mode := fmOpenReadWrite or fmShareDenyWrite
    else
      Mode := fmCreate or fmShareDenyWrite;
    FFileStream := TFileStream.Create(AFileName, Mode);
    FFileStream.Position := FFileStream.Size;
    FCurrentLogFileName := AFileName;
  except
    FreeAndNil(FFileStream);
    raise;
  end;
end;

procedure TAsyncLogger.CleanupOldLogs;
var
  LSR: TSearchRec;
  LBackupDir, LFileName, LDest: string;
begin
  LBackupDir := TPath.Combine(FLogFilePath, 'Backup'); // ExtractFilePath(FCurrentLogFileName) + 'Backup\';
  if not TDirectory.Exists(LBackupDir) then
    TDirectory.CreateDirectory(LBackupDir);

  if System.SysUtils.FindFirst(TPath.Combine(FLogFilePath, '*.log'), faAnyFile, LSR) = 0 then
  try
    repeat
      if (LSR.Attr and faDirectory) <> 0 then
        Continue;
      if DaysBetween(Now, LSR.CreationTime) > MIN_CLEANUP_DAYS then
      begin
        LFileName := TPath.Combine(FLogFilePath, LSR.Name);
        LDest := TPath.Combine(LBackupDir, LSR.Name);
        try
          TFile.Move(LFileName, LDest);
        except
          // �����ƶ�ʧ�ܣ��ļ���ռ�õȣ�
        end;
      end;
    until System.SysUtils.FindNext(LSR) <> 0;
  finally
    System.SysUtils.FindClose(LSR);
  end;

//  FLastCleanupTime := Now;
end;

procedure TAsyncLogger.CloseStreamSafe;
begin
  try
    if Assigned(FFileStream) then
      FreeAndNil(FFileStream);
    FCurrentLogFileName := '';
  except
    // swallow
  end;
end;

function TAsyncLogger.MakeBackupName(const AFileName: string): string;
var
  LBase, LExt, LTs: string;
begin
  LBase := TPath.GetFileNameWithoutExtension(AFileName);
  LExt := TPath.GetExtension(AFileName);
  LTs := FormatDateTime('yyyymmdd_hhnnss', Now);
  Result := TPath.Combine(ExtractFilePath(AFileName), LBase + '_' + LTs + LExt);
end;

procedure TAsyncLogger.RotateBySizeIfNeeded;
var
  LCurFile, LBackup: string;
begin
  if (LOG_FILE_MAX_SIZE_IN_BYTE <= 0) or (not Assigned(FFileStream)) then
    Exit;

  if FFileStream.Size >= LOG_FILE_MAX_SIZE_IN_BYTE then
  begin
    LCurFile := FCurrentLogFileName;
    CloseStreamSafe;
    LBackup := MakeBackupName(LCurFile);
    try
      TFile.Move(LCurFile, LBackup);
    except
      // swallow
    end;
    // create new stream
    try
      CreateNewStream(LCurFile);
    except
      // swallow; writer will attempt again later
    end;
  end;
end;

procedure TAsyncLogger.RotateByDateIfNeeded;
var
  Target: string;
begin
  Target := GetLogFileNameForNow;
  if (FCurrentLogFileName = '') or (not Assigned(FFileStream))  or (not SameText(FCurrentLogFileName, Target)) then
  begin
    if FCurrentLogFileName <> '' then
      CleanupOldLogs;
    CloseStreamSafe;
    CreateNewStream(Target);
  end;
end;

procedure TAsyncLogger.WriterThreadProc;
var
  LocalQueue: TQueue<TLogItem>;
  Item: TLogItem;
begin
  while not FTerminate do
  begin
    if FNewItemEvent.WaitFor(WRITER_THREAD_INTERVAL) = wrSignaled then
    begin
      AcquireSRWLockExclusive(FQueueLock);
      try
        if FQueue.Count = 0 then
          Continue;
        LocalQueue := FQueue;
        FQueue := TQueue<TLogItem>.Create;
      finally
        ReleaseSRWLockExclusive(FQueueLock);
      end;

      try
        try
          RotateByDateIfNeeded;
        except
          OutputDebugString(PChar(Format('�������д��־�ļ� %s ʧ�ܣ����� %d ����־', [
            FCurrentLogFileName, LocalQueue.Count])));
          LocalQueue.Clear;
          if FTerminate then
            Break
          else
            Continue;
        end; // try .. except

        // write all items
        while LocalQueue.Count > 0 do
        begin
          Item := LocalQueue.Dequeue;
          try
            FFileStream.WriteBuffer(Item.Bytes[0], Length(Item.Bytes));
          except
            // swallow
          end;
        end; // for

        RotateBySizeIfNeeded;
        if FTerminate then
          Break;
      finally
        LocalQueue.Free;
      end; // try .. finally ( LocalQueue )
    end // if FEvent.WaitFor(WRITER_THREAD_INTERVAL) = wrSignaled
    else begin
      if FTerminate then
        Break
      else
        Continue;
    end; // if FEvent.WaitFor(WRITER_THREAD_INTERVAL) = wrSignaled .. else
  end; // while

  if not Assigned(FFileStream) then
    Exit;

  // final drain: in case termination requested, drain any remaining queued items
  AcquireSRWLockExclusive(FQueueLock);
  try
    if FQueue.Count = 0 then
      Exit;
    LocalQueue := FQueue;
    FQueue := TQueue<TLogItem>.Create;
  finally
    ReleaseSRWLockExclusive(FQueueLock);
  end;

  try
    while LocalQueue.Count > 0 do
    begin
      Item := LocalQueue.Dequeue;
      try
        FFileStream.WriteBuffer(Item.Bytes[0], Length(Item.Bytes));
      except
        // swallow
      end;
    end; // for
  finally
    LocalQueue.Free;
  end; // try .. finally ( LocalQueue )
end;

procedure TAsyncLogger.Log(const AText: string; ALogLevel: TLogLevel);
var
  Line: string;
  Bytes: TBytes;
  LWriteLog: Boolean;
  Item: TLogItem;
begin
  if Byte(Ord(ALogLevel)) < WRITE_LOG_MIN_LEVEL then
    Exit;

  AcquireSRWLockExclusive(FQueueLock);
  try
    if FFilterLog then
    begin
      if FDistinguishSendRecv then
      begin
        if string.StartsText(FSendPrefix, AText) then
        begin
          LWriteLog := (not SameText(FPrevSendLog, AText)) or (FPrevSendLogLevel <> ALogLevel);
          if LWriteLog then
          begin
            FPrevSendLog := AText;
            FPrevSendLogLevel := ALogLevel;
          end;
        end // if isSendLog
        else if string.StartsText(FRecvPrefix, AText) then
        begin
          LWriteLog := (not SameText(FPrevRecvLog, AText)) or (FPrevRecvLogLevel <> ALogLevel);
          if LWriteLog then
          begin
            FPrevRecvLog := AText;
            FPrevRecvLogLevel := ALogLevel;
          end;
        end // if isRecvLog
        else
          LWriteLog := True;
      end // if FDistinguishSendRecv then
      else begin
        LWriteLog := (not SameText(FPrevSendLog, AText)) or (FPrevSendLogLevel <> ALogLevel);
        if LWriteLog then
        begin
          FPrevSendLog := AText;
          FPrevSendLogLevel := ALogLevel;
        end;
      end; // if FDistinguishSendRecv then .. else
    end // if FFilterLog then
    else
      LWriteLog := True;

    if not LWriteLog then
      Exit;

    try
      case ALogLevel of
        llDetailDebug: Line := '[Detail]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llDebug: Line := '[Debug]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llInfo: Line := '[Info]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llWarning: Line := '[Warning]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llError: Line := '[Error]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llFatal: Line := '[Fatal]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
        llUnknown: Exit;
      end;
    except
      Line := AText + sLineBreak;
    end;

    Bytes := TEncoding.UTF8.GetBytes(Line);
    if Length(Bytes) = 0 then
      Exit;

    Item.Bytes := Bytes;
    Item.Level := ALogLevel;

    if FQueue.Count >= MAX_QUEUE_ITEMS then
      // queue full: drop oldest to keep memory bounded
      FQueue.Dequeue;
    FQueue.Enqueue(Item);
  finally
    ReleaseSRWLockExclusive(FQueueLock);
  end;

  SetLength(Item.Bytes, 0);
  // wake writer
  FNewItemEvent.SetEvent;
end;

procedure TAsyncLogger.LogFmt(const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel);
var
  S: string;
begin
  try
    S := Format(AFormat, AArgs);
  except
    S := AFormat;
  end;
  Log(S, ALogLevel);
end;

procedure TAsyncLogger.Flush;
begin
  // wake writer and wait a short while for it to drain
  if Assigned(FNewItemEvent) then
  begin
    FNewItemEvent.SetEvent;
    Sleep(20);
  end;
end;

{ TLoggerPool }

constructor TLoggerPool.Create(const ABasePath: string);
begin
  inherited Create;
  FBasePath := ABasePath;
  InitializeCriticalSection(FLock);
  FLoggers := TObjectDictionary<string, TAsyncLogger>.Create([doOwnsValues]);
end;

destructor TLoggerPool.Destroy;
begin
  try
    ShutdownAll;
  finally
    FLoggers.Free;
    DeleteCriticalSection(FLock);
  end;

end;

function TLoggerPool.GetLogger(const ALoggerName, ALogFilePath, ALogFileNamePrefix: string;
  AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): TAsyncLogger;
var
  LLogger: TAsyncLogger;
begin
  Result := nil;
  EnterCriticalSection(FLock);
  try
    if not FLoggers.TryGetValue(ALoggerName, LLogger) then
    begin
      LLogger := TAsyncLogger.Create(ALoggerName, ALogFilePath, ALogFileNamePrefix, AFilterLog,
        ADistinguishSendRecv, ASendPrefix, ARecvPrefix);
      FLoggers.Add(ALoggerName, LLogger);
    end;
    Result := LLogger;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLoggerPool.FlushAll;
var
  LLogger: TAsyncLogger;
begin
  EnterCriticalSection(FLock);
  try
    for LLogger in FLoggers.Values do
      LLogger.Flush;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TLoggerPool.ShutdownAll;
var
  LLogger: TAsyncLogger;
begin
  EnterCriticalSection(FLock);
  try
    for LLogger in FLoggers.Values do
      LLogger.Free; // doOwnsValues ���Զ�����
    FLoggers.Clear;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.

