/**
 * 账号类型定义
 * 移植自: FCLCore/src/main/java/com/tungsten/fclcore/auth/
 */

/** 账户类型枚举 */
export enum AccountType {
  OFFLINE = 'offline',
  MICROSOFT = 'microsoft',
  AUTH_LIB_INJECTOR = 'authlib-injector',
  YGGDRASIL = 'yggdrasil'
}

/** 认证信息 (对应 AuthInfo) */
export class AuthInfo {
  username: string;
  uuid: string;
  accessToken: string;
  userType: string;
  userProperties: Record<string, string>;

  constructor(username: string, uuid: string, accessToken: string,
    userType: string = 'mojang', userProperties: Record<string, string> = {}) {
    this.username = username;
    this.uuid = uuid;
    this.accessToken = accessToken;
    this.userType = userType;
    this.userProperties = userProperties;
  }

  /** 获取显示用的角色名 */
  get displayName(): string {
    return this.username;
  }

  /** 判断是否为有效认证 */
  isValid(): boolean {
    return this.accessToken.length > 0 && this.uuid.length > 0;
  }

  toJSON(): Record<string, Object> {
    return {
      username: this.username,
      uuid: this.uuid,
      accessToken: this.accessToken,
      userType: this.userType,
      userProperties: this.userProperties
    };
  }

  static fromJSON(json: Record<string, Object>): AuthInfo {
    return new AuthInfo(
      json['username'] as string ?? '',
      json['uuid'] as string ?? '',
      json['accessToken'] as string ?? '',
      json['userType'] as string ?? 'mojang',
      json['userProperties'] as Record<string, string> ?? {}
    );
  }
}

/** 认证异常 */
export class AuthenticationException extends Error {
  constructor(message: string, public readonly cause?: Error) {
    super(message);
    this.name = 'AuthenticationException';
  }
}

/** 凭证过期异常 */
export class CredentialExpiredException extends AuthenticationException {
  constructor(message: string = 'Credentials have expired') {
    super(message);
    this.name = 'CredentialExpiredException';
  }
}

/** 角色被删除异常 */
export class CharacterDeletedException extends AuthenticationException {
  constructor(message: string = 'Character has been deleted') {
    super(message);
    this.name = 'CharacterDeletedException';
  }
}

/** 无角色异常 */
export class NoCharacterException extends AuthenticationException {
  constructor(message: string = 'No character available') {
    super(message);
    this.name = 'NoCharacterException';
  }
}

/** 未登录异常 */
export class NotLoggedInException extends AuthenticationException {
  constructor(message: string = 'Not logged in') {
    super(message);
    this.name = 'NotLoggedInException';
  }
}

/** 服务端断开连接异常 */
export class ServerDisconnectException extends AuthenticationException {
  constructor(message: string = 'Server disconnected') {
    super(message);
    this.name = 'ServerDisconnectException';
  }
}

/** 服务端响应格式异常 */
export class ServerResponseMalformedException extends AuthenticationException {
  constructor(message: string = 'Server response is malformed') {
    super(message);
    this.name = 'ServerResponseMalformedException';
  }
}

/** 账号类型 (对应 Account 抽象类) */
export interface Account {
  /** 账户用户名 */
  readonly username: string;
  /** 角色名 */
  readonly character: string;
  /** 角色 UUID */
  readonly uuid: string;
  /** 账户类型 */
  readonly type: AccountType;
  /** 唯一标识符 */
  readonly identifier: string;

  /** 登录获取 AuthInfo */
  logIn(): Promise<AuthInfo>;
  /** 离线模式 */
  playOffline(): Promise<AuthInfo>;
  /** 序列化为存储格式 */
  toStorage(): Record<string, Object>;
  /** 清除缓存 */
  clearCache(): void;
}

/** 角色选择器中的角色信息 */
export interface CharacterInfo {
  uuid: string;
  name: string;
}
