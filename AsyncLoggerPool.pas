unit AsyncLoggerPool;
//=======================================================================
//    异步日志及日志池类 (TAsyncLogger & TLoggerPool) ver.1.0
//    DnToHi  ( DnToHi#gmail.com)
//    2025/10/08
//    日志级别约定 ( LogLevel ) ：
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
  System.SyncObjs, System.DateUtils, System.IOUtils, System.Types,
  Winapi.Windows;

const
  WRITE_LOG_DIR                     = 'Log';                  // 日志文件默认目录
  DEFAULT_GLOBAL_LOGGER_NAME        = 'DefaultGlobalLogger';  // 默认全局日志对象名称
  DEFAULT_LOG_FILENAME_PREFIX       = 'Log';                  // 默认日志文件名前缀
  LOG_ERROR_SUCCESS                 = 1;                      // 成功
  LOG_ERROR_LOGGER_NAME_NULL        = -1;                     // 日志对象名称为空
  LOG_ERROR_LOGGERPOOL_NOT_INIT     = -2;                     // 尚未初始化日志池
  LOG_ERROR_INVALID_PATH_CHARS      = -11;                    // 传入的日志路径有非法字符
  LOG_ERROR_INVALID_FILENAME_CHARS  = -12;                    // 传入的文件名前缀有非法字符
  LOG_ERROR_IS_UNCPATH              = -13;                    // 不允许网络路径
  LOG_ERROR_IS_DRIVEROOT_PATH       = -14;                    // 不允许直接指定绝对根路径
  LOG_ERROR_PATH_TRAVERSAL          = -15;                    // 不允许路径逃逸
  LOG_ERROR_SEND_PREFIX_NULL        = -16;                    // 不允许发送日志前缀为空
  LOG_ERROR_RECV_PREFIX_NULL        = -17;                    // 不允许接收日志前缀为空
  LOG_ERROR_SAME_PREFIX             = -18;                    // 不允许发送日志前缀与接收日志前缀相同

type
  TLogRootPathType = (lrpAppPath { lrpModulePath, default }, lrpDocumentsPath, lrpCachePath, lrpHomePath);
  TLogLevel = (llDetailDebug, llDebug, llInfo, llWarning, llError, llFatal, llUnknown);

const
  {$WRITEABLECONST ON}
  WRITE_LOG_MIN_LEVEL: Byte = Ord(llDetailDebug);             // 写日志的最低级别，小于此级别不记录，默认 llDetailDebug
  WRITE_LOG_TIME_FORMAT: string = 'yyyy-mm-dd hh:nn:ss.zzz';  // 写日志添加时间的格式
  LOG_FILE_MAX_SIZE_IN_BYTE: NativeInt = 20 * 1024 * 1024;    // 日志文件最大大小（字节），默认 20M
  MAX_LOG_PATH_LENGTH: Byte = 100;                            // 允许的日志文件子路径最大长度
  MAX_LOG_FILENAME_PREFIX_LENGTH: Byte = 20;                  // 允许的日志文件名称前缀最大长度
  MAX_LOG_ITEM_PREFIX_LENGTH: Byte = 20;                      // 允许的日志内容前缀最大长度
  MAX_QUEUE_ITEMS: NativeInt = 20000;                         // 日志条目列表最大容量，超出时舍弃最早的日志条目
  MIN_CLEANUP_DAYS: NativeInt = 31;                           // 日志文件目录中最多存储多少天的日志，超出时移动至 backup 子目录中
  WRITER_THREAD_INTERVAL: Cardinal = 100;                     // 写日志线程轮询时间间隔（毫秒）
  {$WRITEABLECONST OFF}

type
  TAsyncLogger = class
  private
    type
      TLogItem = record
        Bytes: TBytes;
        Level: TLogLevel;
      end;
  private
    FQueue: TQueue<TLogItem>;                               // 待写入日志条目列表
    FQueueLock: TRTLSRWLock;                                // 日志条目列表操作锁

    FWriterThread: TThread;                                 // 将日志条目写入磁盘文件的线程
    FNewItemEvent: TEvent;                                  // 有新的日志条目
    FFlushEvent: TEvent;                                    // 写入日志条目完成
    FTerminate: Boolean;                                    // 是否要退出

    FFileStream: TFileStream;                               // 文件流，仅在写线程中操作
    FCurrentLogFileName: string;                            // 当前日志文件名称
    FCurrentLogTime: TDateTime;                             // 当前日志文件所属时间

    FPrevSendLog: string;                                   // 上一次发送日志的内容，当不区分发送接收时为上一次的日志内容
    FPrevSendLogLevel: TLogLevel;                           // 上一次发送日志的等级，当不区分发送接收时为上一次的日志等级
    FPrevRecvLog: string;                                   // 上一次接收日志的内容
    FPrevRecvLogLevel: TLogLevel;                           // 上一次接收日志的等级

    FLoggerName: string;                                    // 日志对象的名称
    FLogFilePath: string;                                   // 日志文件所在目录
    FLogFileNamePrefix: string;                             // 日志文件名前缀

    FFilterLog: Boolean;                                    // 是否过滤日志内容
    FDistinguishSendRecv: Boolean;                          // 日志是否区分发送和接收
    FSendPrefix: string;                                    // 发送日志的前缀
    FRecvPrefix: string;                                    // 接收日志的前缀

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

    procedure Flush;                                        // 可选过程，强制唤醒写日志线程，将尚未写入磁盘的日志条目写入磁盘

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

  function CreateGlobalLogger(const ALogPath: string = WRITE_LOG_DIR;
    const ALogFileNamePrefix: string = DEFAULT_LOG_FILENAME_PREFIX;
    ALogRootPathType: TLogRootPathType = lrpAppPath;
    const ALoggerName: string = DEFAULT_GLOBAL_LOGGER_NAME;
    AFilterLog: Boolean = True;
    ADistinguishSendRecv: Boolean = True;
    const ASendPrefix: string = '';
    const ARecvPrefix: string = ''): NativeInt;
  procedure FreeGlobalLogger;
  procedure WriteLog(const AText: string; ALogLevel: TLogLevel = llDetailDebug); overload;
  procedure WriteLogFmt(const AFormat: string; const AArgs: array of const; ALogLevel: TLogLevel = llDetailDebug); overload;

  function CreateGlobalLoggerPool(ALogRootPathType: TLogRootPathType = lrpAppPath): NativeInt;
  procedure FreeGlobalLoggerPool;
  function GetLogger(out ALogger: TAsyncLogger; const ALoggerName, ALogPath, ALogFileNamePrefix: string;
    AFilterLog: Boolean = False; ADistinguishSendRecv: Boolean = False; const ASendPrefix: string = '';
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
  LLogRootPath: string;
begin
  if Assigned(GlobalLoggerPool) then
    Exit(LOG_ERROR_SUCCESS);

  case ALogRootPathType of
    lrpDocumentsPath: LLogRootPath := TPath.Combine(TPath.GetDocumentsPath, 'DnToHi');
    lrpCachePath: LLogRootPath := TPath.Combine(TPath.GetCachePath, 'DnToHi');
    lrpHomePath: LLogRootPath := TPath.Combine(TPath.GetHomePath, 'DnToHi');
    else begin
      if IsLibrary then
        LLogRootPath := ExtractFilePath(System.SysUtils.GetModuleName(HInstance))
      else
        LLogRootPath := ExtractFilePath(ParamStr(0));
    end;
  end;
  LLogRootPath := IncludeTrailingPathDelimiter(LLogRootPath);
  GlobalLoggerPool := TLoggerPool.Create(LLogRootPath);
  Result := LOG_ERROR_SUCCESS;
end;

procedure FreeGlobalLoggerPool;
begin
  FreeAndNil(GlobalLoggerPool);
end;

function GetLogger(out ALogger: TAsyncLogger;const ALoggerName, ALogPath, ALogFileNamePrefix: string;
  AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): NativeInt;
var
  LLogPath, LLogFileNamePrefix, LSendPrefix, LRecvPrefix: string;
begin
  ALogger := nil;
  if not Assigned(GlobalLoggerPool) then
    Exit(LOG_ERROR_LOGGERPOOL_NOT_INIT);

  if Trim(ALoggerName) = '' then
    Exit(LOG_ERROR_LOGGER_NAME_NULL);

  if not TPath.HasValidPathChars(ALogPath, False) then
    Exit(LOG_ERROR_INVALID_PATH_CHARS);

  if not TPath.HasValidFileNameChars(ALogFileNamePrefix, False) then
    Exit(LOG_ERROR_INVALID_FILENAME_CHARS);

  if TPath.IsUNCPath(ALogPath) then
    Exit(LOG_ERROR_IS_UNCPATH);

  if TPath.IsDriveRooted(ALogPath) then
    Exit(LOG_ERROR_IS_DRIVEROOT_PATH);

  if ALogPath = '' then
    LLogPath := WRITE_LOG_DIR
  else if Length(ALogPath) > MAX_LOG_PATH_LENGTH then
    LLogPath := ALogPath.Substring(0, MAX_LOG_PATH_LENGTH)
  else
    LLogPath := ALogPath;
  LLogPath := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(GlobalLoggerPool.FBasePath, LLogPath)));
  if not LLogPath.StartsWith(GlobalLoggerPool.FBasePath, True) then
    Exit(LOG_ERROR_PATH_TRAVERSAL);
  if Length(ALogFileNamePrefix) > MAX_LOG_FILENAME_PREFIX_LENGTH then
    LLogFileNamePrefix := ALogFileNamePrefix.Substring(0, MAX_LOG_FILENAME_PREFIX_LENGTH)
  else
    LLogFileNamePrefix := ALogFileNamePrefix;
  if AFilterLog and ADistinguishSendRecv then
  begin
    LSendPrefix := Trim(ASendPrefix);
    if LSendPrefix = '' then
      Exit(LOG_ERROR_SEND_PREFIX_NULL)
    else if Length(LSendPrefix) > MAX_LOG_ITEM_PREFIX_LENGTH then
      LSendPrefix := LSendPrefix.Substring(0, MAX_LOG_ITEM_PREFIX_LENGTH);

    LRecvPrefix := Trim(ARecvPrefix);
    if LRecvPrefix = '' then
      Exit(LOG_ERROR_RECV_PREFIX_NULL)
    else if Length(LRecvPrefix) > MAX_LOG_ITEM_PREFIX_LENGTH then
      LRecvPrefix := LRecvPrefix.Substring(0, MAX_LOG_ITEM_PREFIX_LENGTH);

    if SameText(LSendPrefix, LRecvPrefix) then
      Exit(LOG_ERROR_SAME_PREFIX);
  end;
  ALogger := GlobalLoggerPool.GetLogger(ALoggerName, LLogPath, LLogFileNamePrefix, AFilterLog,
    ADistinguishSendRecv, LSendPrefix, LRecvPrefix);
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

function CreateGlobalLogger(const ALogPath, ALogFileNamePrefix: string; ALogRootPathType: TLogRootPathType;
  const ALoggerName: string; AFilterLog, ADistinguishSendRecv: Boolean;
  const ASendPrefix, ARecvPrefix: string): NativeInt;
var
  LLogRootPath, LLogPath, LLogFileNamePrefix, LSendPrefix, LRecvPrefix: string;
begin
  if Assigned(GlobalLogger) then
    Exit(LOG_ERROR_SUCCESS);

  if Trim(ALoggerName) = '' then
    Exit(LOG_ERROR_LOGGER_NAME_NULL);

  if not TPath.HasValidPathChars(ALogPath, False) then
    Exit(LOG_ERROR_INVALID_PATH_CHARS);

  if not TPath.HasValidFileNameChars(ALogFileNamePrefix, False) then
    Exit(LOG_ERROR_INVALID_FILENAME_CHARS);

  if TPath.IsUNCPath(ALogPath) then
    Exit(LOG_ERROR_IS_UNCPATH);

  if TPath.IsDriveRooted(ALogPath) then
    Exit(LOG_ERROR_IS_DRIVEROOT_PATH);

  case ALogRootPathType of
    lrpDocumentsPath: LLogRootPath := TPath.Combine(TPath.GetDocumentsPath, 'DnToHi');
    lrpCachePath: LLogRootPath := TPath.Combine(TPath.GetCachePath, 'DnToHi');
    lrpHomePath: LLogRootPath := TPath.Combine(TPath.GetHomePath, 'DnToHi');
    else begin
      if IsLibrary then
        LLogRootPath := ExtractFilePath(System.SysUtils.GetModuleName(HInstance))
      else
        LLogRootPath := ExtractFilePath(ParamStr(0));
    end;
  end;
  LLogRootPath := IncludeTrailingPathDelimiter(LLogRootPath);
  if ALogPath = '' then
    LLogPath := WRITE_LOG_DIR
  else if Length(ALogPath) > MAX_LOG_PATH_LENGTH then
    LLogPath := ALogPath.Substring(0, MAX_LOG_PATH_LENGTH)
  else
    LLogPath := ALogPath;
  LLogPath := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(LLogRootPath, LLogPath)));
  if not LLogPath.StartsWith(LLogRootPath, True) then
    Exit(LOG_ERROR_PATH_TRAVERSAL);
  if Length(ALogFileNamePrefix) > MAX_LOG_FILENAME_PREFIX_LENGTH then
    LLogFileNamePrefix := ALogFileNamePrefix.Substring(0, MAX_LOG_FILENAME_PREFIX_LENGTH)
  else
    LLogFileNamePrefix := ALogFileNamePrefix;
  if AFilterLog and ADistinguishSendRecv then
  begin
    LSendPrefix := Trim(ASendPrefix);
    if LSendPrefix = '' then
      Exit(LOG_ERROR_SEND_PREFIX_NULL)
    else if Length(LSendPrefix) > MAX_LOG_ITEM_PREFIX_LENGTH then
      LSendPrefix := LSendPrefix.Substring(0, MAX_LOG_ITEM_PREFIX_LENGTH);

    LRecvPrefix := Trim(ARecvPrefix);
    if LRecvPrefix = '' then
      Exit(LOG_ERROR_RECV_PREFIX_NULL)
    else if Length(LRecvPrefix) > MAX_LOG_ITEM_PREFIX_LENGTH then
      LRecvPrefix := LRecvPrefix.Substring(0, MAX_LOG_ITEM_PREFIX_LENGTH);

    if SameText(LSendPrefix, LRecvPrefix) then
      Exit(LOG_ERROR_SAME_PREFIX);
  end;
  GlobalLogger := TAsyncLogger.Create(ALoggerName, LLogPath, LLogFileNamePrefix, AFilterLog, ADistinguishSendRecv,
    LSendPrefix, LRecvPrefix);
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
  L := GlobalLogger;
  if Assigned(L) then
  begin
    try
      L.Log(AText, ALogLevel);
    except
      // swallow
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
  FFlushEvent := TEvent.Create(nil, True, False, '');
  FTerminate := False;

  FFileStream := nil; // delayed creation, it will be created when it is used the first time

  FCurrentLogFileName := '';
  FCurrentLogTime := 0;

  FPrevSendLog := '';
  FPrevSendLogLevel := llUnknown;
  FPrevRecvLog := '';
  FPrevRecvLogLevel := llUnknown;

  FWriterThread := TThread.CreateAnonymousThread(WriterThreadProc);
  FWriterThread.FreeOnTerminate := False;
  FWriterThread.Start;
  Self.Log('创建/打开日志文件', llInfo);
end;

destructor TAsyncLogger.Destroy;
begin
//  Flush;
  Self.Log('关闭日志文件', llInfo);
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
  if Assigned(FFlushEvent) then
    FreeAndNil(FFlushEvent);
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
  LBackupDir, LFileName: string;
  LFiles: TStringDynArray;
  LFileDate: TDateTime;
begin
  LBackupDir := TPath.Combine(FLogFilePath, 'Backup');
  if not TDirectory.Exists(LBackupDir) then
    TDirectory.CreateDirectory(LBackupDir);

  LFiles := TDirectory.GetFiles(FLogFilePath, '*.log');
  for LFileName in LFiles do
  begin
    try
      LFileDate := TFile.GetCreationTime(LFileName);
      if DaysBetween(Now, LFileDate) > MIN_CLEANUP_DAYS then
        TFile.Move(LFileName, TPath.Combine(LBackupDir, ExtractFileName(LFileName)));
    except
      // 忽略移动失败（文件被占用等）
    end;
  end; // for
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
        if FQueue.Count > 0 then
        begin
          LocalQueue := FQueue;
          FQueue := TQueue<TLogItem>.Create;
        end
        else
          LocalQueue := nil;
      finally
        ReleaseSRWLockExclusive(FQueueLock);
      end;

      if not Assigned(LocalQueue) then
        Continue;

      try
        try
          RotateByDateIfNeeded;
        except
          OutputDebugString(PChar(Format('创建或读写日志文件 %s 失败，丢弃 %d 条日志',
            [FCurrentLogFileName, LocalQueue.Count])));
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

        if Assigned(FFlushEvent) then
          FFlushEvent.SetEvent;
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
        if AText.StartsWith(FSendPrefix, True) then
        begin
          LWriteLog := (not SameText(FPrevSendLog, AText)) or (FPrevSendLogLevel <> ALogLevel);
          if LWriteLog then
          begin
            FPrevSendLog := AText;
            FPrevSendLogLevel := ALogLevel;
          end;
        end // if isSendLog
        else if AText.StartsWith(FRecvPrefix, True) then
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
  finally
    ReleaseSRWLockExclusive(FQueueLock);
  end;

  if not LWriteLog then
    Exit;

  try
    case ALogLevel of
      llDetailDebug: Line := '[V]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
      llDebug: Line := '[D]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
      llInfo: Line := '[I]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
      llWarning: Line := '[W]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
      llError: Line := '[E]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
      llFatal: Line := '[F]' + #9 + FormatDateTime(WRITE_LOG_TIME_FORMAT, Now) + #9 + AText + sLineBreak;
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

  AcquireSRWLockExclusive(FQueueLock);
  try
    if FQueue.Count >= MAX_QUEUE_ITEMS then
      FQueue.Dequeue; // queue full: drop oldest to keep memory bounded
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
  if not Assigned(FNewItemEvent) then
    Exit;
  if Assigned(FFlushEvent) then
    FFlushEvent.ResetEvent;
  FNewItemEvent.SetEvent;
  if Assigned(FFlushEvent) then
    FFlushEvent.WaitFor(5000); // 等 5 秒
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
//    FlushAll;
    ShutdownAll;
  finally
    FLoggers.Free;
    DeleteCriticalSection(FLock);
  end;
  inherited;
end;

function TLoggerPool.GetLogger(const ALoggerName, ALogFilePath, ALogFileNamePrefix: string;
  AFilterLog, ADistinguishSendRecv: Boolean; const ASendPrefix, ARecvPrefix: string): TAsyncLogger;
var
  LLogger: TAsyncLogger;
begin
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
begin
  EnterCriticalSection(FLock);
  try
    FLoggers.Clear; // doOwnsValues 会自动清理
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
