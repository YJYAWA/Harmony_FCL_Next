/**
 * 离线账号实现
 * 移植自: FCLCore/src/main/java/com/tungsten/fclcore/auth/offline/
 */
import { Account, AuthInfo, CharacterInfo, AccountType, AuthenticationException }
  from './AuthTypes';
import { uuidv4, offlinePlayerUUID } from '../util/UUIDUtils';

/** 离线账号配置 */
export interface OfflineAccountConfig {
  username: string;
  uuid?: string;
}

/**
 * 离线账号 - 不需要网络验证的本地账号
 */
export class OfflineAccount implements Account {
  readonly type: AccountType = AccountType.OFFLINE;
  private _username: string;
  private _uuid: string;

  constructor(config: OfflineAccountConfig) {
    this._username = config.username;
    this._uuid = config.uuid ?? offlinePlayerUUID(config.username);
  }

  get username(): string {
    return this._username;
  }

  get character(): string {
    return this._username;
  }

  get uuid(): string {
    return this._uuid;
  }

  get identifier(): string {
    return `offline:${this._username}`;
  }

  async logIn(): Promise<AuthInfo> {
    if (!this._username || this._username.trim().length === 0) {
      throw new AuthenticationException('Username cannot be empty');
    }
    return new AuthInfo(this._username, this._uuid, 'offline-token', 'mojang');
  }

  async playOffline(): Promise<AuthInfo> {
    return this.logIn();
  }

  toStorage(): Record<string, Object> {
    return {
      type: AccountType.OFFLINE,
      username: this._username,
      uuid: this._uuid
    };
  }

  clearCache(): void {
    // 离线账号无需清除缓存
  }

  /** 从存储恢复 */
  static fromStorage(data: Record<string, Object>): OfflineAccount {
    return new OfflineAccount({
      username: data['username'] as string,
      uuid: data['uuid'] as string
    });
  }
}
