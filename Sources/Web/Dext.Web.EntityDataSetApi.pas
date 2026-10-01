{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}
unit Dext.Web.EntityDataSetApi;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Rtti,
  Data.DB,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Entity,
  Dext.Entity.Context,
  Dext.Entity.Mapping,
  Dext.Json,
  Dext.Json.Types,
  Dext.Web.Interfaces,
  Dext.Web.Routing;

type
  /// <summary>
  /// Represents the result of applying a single change item.
  /// </summary>
  TApplyItemResult = record
    /// <summary>The index of the change in the incoming list.</summary>
    Index: Integer;
    /// <summary>True if the change was applied successfully.</summary>
    Success: Boolean;
    /// <summary>Detailed error message in case of failure.</summary>
    ErrorMessage: string;
    /// <summary>Database keys (e.g. autoincrement ID).</summary>
    Keys: IDictionary<string, Variant>;
  end;

  /// <summary>
  /// Interface for processing and persisting entity change logs.
  /// </summary>
  IEntityDataSetStore = interface
    ['{F1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}']
    /// <summary>
    /// Persists a batch of entity changes.
    /// </summary>
    function ApplyChanges(AEntityClass: TClass;
      const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
  end;

  /// <summary>
  /// DBContext-based store engine for persisting change logs.
  /// </summary>
  TDbContextEntityDataSetStore = class(TInterfacedObject, IEntityDataSetStore)
  private
    FContinueOnError: Boolean;
    function GetEntityKeys(AEntity: TObject;
      Map: TEntityMap): IDictionary<string, Variant>;
    function ReadPropertyValue(AEntity: TObject;
      PropMap: TPropertyMap; out Value: Variant): Boolean;
    procedure SetPropertyValue(AEntity: TObject;
      PropMap: TPropertyMap; const Value: Variant);
    function StageChange(AEntityClass: TClass; Map: TEntityMap;
      const AChange: IDextJsonObject; ADbContext: TDbContext): TObject;
    function ApplyAtomic(AEntityClass: TClass; const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
    function ApplyEachItem(AEntityClass: TClass; const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
  public
    /// <summary>
    /// Creates the store. By default a batch is applied all-or-nothing.
    /// </summary>
    /// <param name="AContinueOnError">See ContinueOnError.</param>
    constructor Create(AContinueOnError: Boolean = False);
    /// <summary>
    /// Persists changes using the ORM DbContext SaveChanges.
    /// By default the whole batch is staged and saved with a single
    /// SaveChanges, in one transaction (the context's own, or the caller's if
    /// one is open): if any item fails, nothing is applied and every item is
    /// reported as failed. With ContinueOnError each item is saved on its own.
    /// </summary>
    function ApplyChanges(AEntityClass: TClass;
      const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
    /// <summary>
    /// Opt-in partial success: each item is saved with its own SaveChanges,
    /// and a failing item is detached so that later items do not retry it.
    /// Items applied before a failure stay committed. Default: False.
    /// </summary>
    property ContinueOnError: Boolean read FContinueOnError write FContinueOnError;
  end;

  /// <summary>
  /// Exposes REST endpoints to load and persist datasets.
  /// </summary>
  TEntityDataSetApi = class
  public
    /// <summary>
    /// Maps GET and POST endpoints for a remote dataset.
    /// </summary>
    class procedure Map<T: class, constructor>(
      const ABuilder: IApplicationBuilder;
      const APath: string;
      ADbContextClass: TClass;
      AStore: IEntityDataSetStore = nil);
  end;

implementation

uses
  Dext.Core.Reflection;

{ TDbContextEntityDataSetStore }

function TDbContextEntityDataSetStore.ReadPropertyValue(AEntity: TObject;
  PropMap: TPropertyMap; out Value: Variant): Boolean;
var
  PValue: Pointer;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  V: TValue;
begin
  Result := False;
  if (AEntity = nil) or (PropMap = nil) then Exit;

  if PropMap.FieldValueOffset > 0 then
  begin
    if (PropMap.FieldOffset > 0) and not
      PBoolean(Pointer(PByte(AEntity) + PropMap.FieldOffset))^ then
    begin
      Value := Null;
      Exit(True);
    end;

    PValue := Pointer(PByte(AEntity) + PropMap.FieldValueOffset);
    case PropMap.DataType of
      ftInteger, ftAutoInc: Value := PInteger(PValue)^;
      ftSmallint: Value := PSmallInt(PValue)^;
      ftShortint: Value := PShortInt(PValue)^;
      ftByte: Value := PByte(PValue)^;
      ftWord: Value := PWord(PValue)^;
      ftLargeint: Value := PInt64(PValue)^;
      ftString, ftWideString: Value := PString(PValue)^;
      ftFloat: Value := PDouble(PValue)^;
      ftCurrency: Value := PCurrency(PValue)^;
      ftBoolean: Value := PBoolean(PValue)^;
      ftDateTime, ftDate, ftTime: Value := PDateTime(PValue)^;
    else
      Exit(False);
    end;
    Result := True;
  end
  else
  begin
    RttiType := TReflection.Context.GetType(AEntity.ClassType);
    if RttiType <> nil then
    begin
      RttiProp := RttiType.GetProperty(PropMap.PropertyName);
      if RttiProp <> nil then
      begin
        V := RttiProp.GetValue(AEntity);
        Value := V.AsVariant;
        Result := True;
      end;
    end;
  end;
end;

procedure TDbContextEntityDataSetStore.SetPropertyValue(AEntity: TObject;
  PropMap: TPropertyMap; const Value: Variant);
var
  PValue: Pointer;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
begin
  if (AEntity = nil) or (PropMap = nil) then Exit;

  if PropMap.FieldValueOffset > 0 then
  begin
    if PropMap.FieldOffset > 0 then
      PBoolean(Pointer(PByte(AEntity) + PropMap.FieldOffset))^ :=
        not VarIsNull(Value);

    if not VarIsNull(Value) then
    begin
      PValue := Pointer(PByte(AEntity) + PropMap.FieldValueOffset);
      case PropMap.DataType of
        ftInteger, ftAutoInc: PInteger(PValue)^ := Value;
        ftSmallint: PSmallInt(PValue)^ := Value;
        ftShortint: PShortInt(PValue)^ := Value;
        ftByte: PByte(PValue)^ := Value;
        ftWord: PWord(PValue)^ := Value;
        ftLargeint: PInt64(PValue)^ := Value;
        ftString, ftWideString: PString(PValue)^ := string(Value);
        ftFloat: PDouble(PValue)^ := Double(Value);
        ftCurrency: PCurrency(PValue)^ := Currency(Value);
        ftBoolean: PBoolean(PValue)^ := Boolean(Value);
        ftDateTime, ftDate, ftTime: PDateTime(PValue)^ := TDateTime(Value);
      end;
    end;
  end;

  RttiType := TReflection.Context.GetType(AEntity.ClassType);
  if RttiType <> nil then
  begin
    RttiProp := RttiType.GetProperty(PropMap.PropertyName);
    if RttiProp <> nil then
    begin
      if VarIsNull(Value) then
        RttiProp.SetValue(AEntity, TValue.Empty)
      else
        RttiProp.SetValue(AEntity, TValue.FromVariant(Value));
    end;
  end;
end;

function TDbContextEntityDataSetStore.GetEntityKeys(AEntity: TObject;
  Map: TEntityMap): IDictionary<string, Variant>;
var
  Pair: TPair<string, TPropertyMap>;
  Val: Variant;
begin
  Result := TCollections.CreateDictionary<string, Variant>;
  if (AEntity <> nil) and (Map <> nil) then
  begin
    for Pair in Map.Properties do
    begin
      if Pair.Value.IsPK then
      begin
        if ReadPropertyValue(AEntity, Pair.Value, Val) then
          Result.Add(Pair.Key, Val);
      end;
    end;
  end;
end;

constructor TDbContextEntityDataSetStore.Create(AContinueOnError: Boolean);
begin
  inherited Create;
  FContinueOnError := AContinueOnError;
end;

function TDbContextEntityDataSetStore.StageChange(AEntityClass: TClass;
  Map: TEntityMap; const AChange: IDextJsonObject;
  ADbContext: TDbContext): TObject;
var
  StateStr: string;
  KeysObj: IDextJsonObject;
  ValuesObj: IDextJsonObject;
  EntityObj: TObject;
  Pair: TPair<string, TPropertyMap>;
begin
  Result := nil;
  StateStr := AChange.GetString('state');
  if not (SameText(StateStr, 'inserted') or SameText(StateStr, 'modified') or
    SameText(StateStr, 'deleted')) then
    Exit;

  KeysObj := nil;
  if AChange.Contains('key') then
    KeysObj := AChange.GetObject('key');
  ValuesObj := nil;
  if AChange.Contains('values') then
    ValuesObj := AChange.GetObject('values');

  EntityObj := AEntityClass.Create;
  try
    if SameText(StateStr, 'inserted') then
    begin
      if (ValuesObj <> nil) and (Map <> nil) then
      begin
        for Pair in Map.Properties do
        begin
          if ValuesObj.Contains(Pair.Key) then
            SetPropertyValue(EntityObj, Pair.Value,
              ValuesObj.GetString(Pair.Key));
        end;
      end;

      ADbContext.ChangeTracker.Track(EntityObj, esAdded);
    end
    else
    begin
      if (KeysObj <> nil) and (Map <> nil) then
      begin
        for Pair in Map.Properties do
        begin
          if Pair.Value.IsPK and KeysObj.Contains(Pair.Key) then
            SetPropertyValue(EntityObj, Pair.Value,
              KeysObj.GetString(Pair.Key));
        end;
      end;

      if SameText(StateStr, 'modified') then
      begin
        ADbContext.ChangeTracker.Track(EntityObj, esUnchanged);

        if (ValuesObj <> nil) and (Map <> nil) then
        begin
          for Pair in Map.Properties do
          begin
            if ValuesObj.Contains(Pair.Key) then
            begin
              SetPropertyValue(EntityObj, Pair.Value,
                ValuesObj.GetString(Pair.Key));
              ADbContext.Entry(EntityObj).Member(Pair.Key).IsModified := True;
            end;
          end;
        end;
      end
      else
        ADbContext.ChangeTracker.Track(EntityObj, esDeleted);
    end;
  except
    // Not saved yet, so nothing else references it.
    ADbContext.ChangeTracker.Remove(EntityObj);
    EntityObj.Free;
    raise;
  end;
  Result := EntityObj;
end;

function TDbContextEntityDataSetStore.ApplyAtomic(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
var
  Results: IList<TApplyItemResult>;
  ItemResult: TApplyItemResult;
  Entities: IList<TObject>;
  Entity: TObject;
  Map: TEntityMap;
  FailedIndex: Integer;
  ErrorMessage: string;
  i: Integer;
begin
  Results := TCollections.CreateList<TApplyItemResult>;
  Entities := TCollections.CreateList<TObject>;
  Map := ADbContext.ModelBuilder.GetMap(AEntityClass.ClassInfo);

  // Stage every item first, then save the whole batch with one SaveChanges:
  // it runs in a single transaction (its own, or the caller's when one is
  // open) and rolls back its own transaction if any statement fails.
  FailedIndex := -1;
  ErrorMessage := '';
  try
    for i := 0 to AChanges.Count - 1 do
    begin
      FailedIndex := i;
      Entities.Add(StageChange(AEntityClass, Map, AChanges.GetObject(i),
        ADbContext));
    end;
    FailedIndex := -1;
    ADbContext.SaveChanges;
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      // A failed SaveChanges leaves the batch tracked: detach it, so that a
      // later SaveChanges on this context does not try to save it again.
      for Entity in Entities do
      begin
        if Entity <> nil then
          ADbContext.Detach(Entity);
      end;
    end;
  end;

  for i := 0 to AChanges.Count - 1 do
  begin
    ItemResult.Index := i;
    ItemResult.Keys := nil;
    if ErrorMessage = '' then
    begin
      ItemResult.Success := True;
      ItemResult.ErrorMessage := '';
      if (Entities[i] <> nil) and
        SameText(AChanges.GetObject(i).GetString('state'), 'inserted') then
        ItemResult.Keys := GetEntityKeys(Entities[i], Map);
    end
    else
    begin
      ItemResult.Success := False;
      if FailedIndex < 0 then
        ItemResult.ErrorMessage := 'Batch not applied: ' + ErrorMessage
      else if i = FailedIndex then
        ItemResult.ErrorMessage := ErrorMessage
      else
        ItemResult.ErrorMessage := Format('Batch not applied: item %d failed (%s)',
          [FailedIndex, ErrorMessage]);
    end;
    Results.Add(ItemResult);
  end;

  Result := Results;
end;

function TDbContextEntityDataSetStore.ApplyEachItem(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
var
  Results: IList<TApplyItemResult>;
  ItemResult: TApplyItemResult;
  EntityObj: TObject;
  Map: TEntityMap;
  i: Integer;
begin
  Results := TCollections.CreateList<TApplyItemResult>;
  Map := ADbContext.ModelBuilder.GetMap(AEntityClass.ClassInfo);

  for i := 0 to AChanges.Count - 1 do
  begin
    ItemResult.Index := i;
    ItemResult.Success := True;
    ItemResult.ErrorMessage := '';
    ItemResult.Keys := nil;

    EntityObj := nil;
    try
      EntityObj := StageChange(AEntityClass, Map, AChanges.GetObject(i),
        ADbContext);
      if EntityObj <> nil then
      begin
        ADbContext.SaveChanges;
        if SameText(AChanges.GetObject(i).GetString('state'), 'inserted') then
          ItemResult.Keys := GetEntityKeys(EntityObj, Map);
      end;
    except
      on E: Exception do
      begin
        ItemResult.Success := False;
        ItemResult.ErrorMessage := E.Message;
        // The failed entity is still tracked: detach it, or the next item's
        // SaveChanges would try to save it again.
        if EntityObj <> nil then
          ADbContext.Detach(EntityObj);
      end;
    end;

    Results.Add(ItemResult);
  end;

  Result := Results;
end;

function TDbContextEntityDataSetStore.ApplyChanges(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
begin
  if FContinueOnError then
    Result := ApplyEachItem(AEntityClass, AChanges, ADbContext)
  else
    Result := ApplyAtomic(AEntityClass, AChanges, ADbContext);
end;

{ TEntityDataSetApi }

class procedure TEntityDataSetApi.Map<T>(
  const ABuilder: IApplicationBuilder;
  const APath: string;
  ADbContextClass: TClass;
  AStore: IEntityDataSetStore);
var
  Store: IEntityDataSetStore;
begin
  if AStore <> nil then
    Store := AStore
  else
    Store := TDbContextEntityDataSetStore.Create;

  ABuilder.MapGet(APath,
    procedure(Context: IHttpContext)
    var
      Ctx: TDbContext;
      List: IList<T>;
      JsonBytes: TBytes;
    begin
      Ctx := TDbContext(ADbContextClass.Create);
      try
        List := Ctx.Entities<T>.ToList;
        JsonBytes := TDextJson.SerializeUtf8(List);
        Context.Response.SetContentType('application/json');
        Context.Response.Write(JsonBytes);
      finally
        Ctx.Free;
      end;
    end);

  ABuilder.MapPost(APath + '/apply',
    procedure(Context: IHttpContext)
    var
      Ctx: TDbContext;
      RequestBody: string;
      JO: IDextJsonObject;
      ChangesArray: IDextJsonArray;
      ApplyResults: IList<TApplyItemResult>;
      ResJson: TBytes;
      Reader: TStreamReader;
    begin
      Reader := TStreamReader.Create(Context.Request.Body, TEncoding.UTF8);
      try
        RequestBody := Reader.ReadToEnd;
      finally
        Reader.Free;
      end;

      JO := TDextJson.Provider.Parse(RequestBody) as IDextJsonObject;
      if (JO <> nil) and JO.Contains('changes') then
      begin
        ChangesArray := JO.GetArray('changes');
        Ctx := TDbContext(ADbContextClass.Create);
        try
          ApplyResults := Store.ApplyChanges(T, ChangesArray, Ctx);
          ResJson := TDextJson.SerializeUtf8(ApplyResults);
          Context.Response.SetContentType('application/json');
          Context.Response.Write(ResJson);
        finally
          Ctx.Free;
        end;
      end;
    end);
end;

end.
