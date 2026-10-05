{***********************************************************************************}
{                                                                                   }
{           Dext Framework                                                          }
{                                                                                   }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors                     }
{                                                                                   }
{           Licensed under the Apache License, Version 2.0 (the "License");         }
{           you may not use this file except in compliance with the License.        }
{           You may obtain a copy of the License at                                 }
{                                                                                   }
{               http://www.apache.org/licenses/LICENSE-2.0                          }
{                                                                                   }
{           Unless required by applicable law or agreed to in writing,              }
{           software distributed under the License is distributed on an             }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,            }
{           either express or implied. See the License for the specific             }
{           language governing permissions and limitations under the                }
{           License.                                                                }
{                                                                                   }
{***********************************************************************************}
{                                                                                   }
{  Description:                                                                     }
{    Custom attributes for RTTI-based MCP registration.                             }
{                                                                                   }
{    Decorate methods on a TMCPToolProvider subclass to auto-register:              }
{                                                                                   }
{      type                                                                         }
{        TMyTools = class(TMCPToolProvider)                                         }
{          [MCPTool('search', 'Full-text search across all records')]               }
{          [MCPParam('query',  'Search term',    ptString)]                         }
{          [MCPParam('limit',  'Max results',    ptInteger, False)]                 }
{          function Search(const Args: TJsonObject): TMCPToolResult; virtual;       }
{                                                                                   }
{          [MCPTool('delete-record', 'Permanently deletes a record')]               }
{          [MCPParam('id', 'Record ID', ptString)]                                  }
{          function DeleteRecord(const Args: TJsonObject): TMCPToolResult; virtual; }
{        end;                                                                       }
{                                                                                   }
{      Server.RegisterProvider(TMyTools.Create);                                    }
{                                                                                   }
{    Resource providers:                                                            }
{      [MCPResource('file:///config.json', 'Config', 'App configuration')]          }
{      function ReadConfig(const AUri: string): TMCPResourceContents; virtual;      }
{                                                                                   }
{    Prompt providers:                                                              }
{      [MCPPrompt('code-review', 'Performs a thorough code review')]                }
{      [MCPPromptArg('language', 'Programming language', False)]                    }
{      function CodeReview(const Args: TJsonObject): TMCPPromptResult; virtual;     }
{                                                                                   }
{***********************************************************************************}
unit Dext.AI.MCP.Attributes;

interface

uses
  System.SysUtils,
  Dext.AI.MCP.Protocol;

type
  // ---------------------------------------------------------------------------
  // Tool attributes
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Marks a provider method as an MCP tool.
  /// The method must have signature: function(const Args: TJsonObject): TMCPToolResult.
  /// </summary>
  MCPToolAttribute = class(TCustomAttribute)
  private
    FName: string;
    FDescription: string;
  public
    constructor Create(const AName, ADescription: string);
    property Name: string read FName;
    property Description: string read FDescription;
  end;

  /// <summary>
  /// Describes one input parameter for an MCPTool method.
  /// Stack multiple MCPParam attributes on the same method for multiple params.
  /// Order of attributes determines schema property order (best-effort).
  /// </summary>
  MCPParamAttribute = class(TCustomAttribute)
  private
    FName: string;
    FDescription: string;
    FParamType: TMCPParamType;
    FRequired: Boolean;
  public
    constructor Create(const AName, ADescription: string;
      AParamType: TMCPParamType = ptString;
      ARequired: Boolean = True);
    property Name: string read FName;
    property Description: string read FDescription;
    property ParamType: TMCPParamType read FParamType;
    property Required: Boolean read FRequired;
  end;

  // ---------------------------------------------------------------------------
  // Resource attributes
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Marks a provider method as an MCP resource reader.
  /// The method must have signature: function(const AUri: string): TMCPResourceContents.
  /// </summary>
  MCPResourceAttribute = class(TCustomAttribute)
  private
    FUri: string;
    FName: string;
    FDescription: string;
    FMimeType: string;
  public
    constructor Create(const AUri, AName, ADescription: string;
      const AMimeType: string = '');
    property Uri: string read FUri;
    property Name: string read FName;
    property Description: string read FDescription;
    property MimeType: string read FMimeType;
  end;

  // ---------------------------------------------------------------------------
  // Prompt attributes
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Marks a provider method as an MCP prompt template.
  /// The method must have signature: function(const Args: TJSONObject): TMCPPromptResult.
  /// </summary>
  MCPPromptAttribute = class(TCustomAttribute)
  private
    FName: string;
    FDescription: string;
  public
    constructor Create(const AName, ADescription: string);
    property Name: string read FName;
    property Description: string read FDescription;
  end;

  /// <summary>
  /// Describes one argument of an MCPPrompt template.
  /// Stack multiple MCPPromptArg attributes for multiple arguments.
  /// </summary>
  MCPPromptArgAttribute = class(TCustomAttribute)
  private
    FName: string;
    FDescription: string;
    FRequired: Boolean;
  public
    constructor Create(const AName, ADescription: string;
      ARequired: Boolean = True);
    property Name: string read FName;
    property Description: string read FDescription;
    property Required: Boolean read FRequired;
  end;

implementation

{ MCPToolAttribute }

constructor MCPToolAttribute.Create(const AName, ADescription: string);
begin
  inherited Create;
  FName        := AName;
  FDescription := ADescription;
end;

{ MCPParamAttribute }

constructor MCPParamAttribute.Create(const AName, ADescription: string;
  AParamType: TMCPParamType; ARequired: Boolean);
begin
  inherited Create;
  FName        := AName;
  FDescription := ADescription;
  FParamType   := AParamType;
  FRequired    := ARequired;
end;

{ MCPResourceAttribute }

constructor MCPResourceAttribute.Create(const AUri, AName, ADescription: string;
  const AMimeType: string);
begin
  inherited Create;
  FUri         := AUri;
  FName        := AName;
  FDescription := ADescription;
  FMimeType    := AMimeType;
end;

{ MCPPromptAttribute }

constructor MCPPromptAttribute.Create(const AName, ADescription: string);
begin
  inherited Create;
  FName        := AName;
  FDescription := ADescription;
end;

{ MCPPromptArgAttribute }

constructor MCPPromptArgAttribute.Create(const AName, ADescription: string;
  ARequired: Boolean);
begin
  inherited Create;
  FName        := AName;
  FDescription := ADescription;
  FRequired    := ARequired;
end;

end.
