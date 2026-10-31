/**
 * 当前账号服务
 *
 * 复用 core/auth 现有的 AccountFactory / OfflineAccount / MicrosoftAccount / YggdrasilAccount，
 * 只补齐「当前选中账号」的持久化与启动参数装配（原实现缺这一层，
 * 导致 MainPage / VersionsPage 只能硬编码 Player + 全零 UUID + offline token）。
 */
import { Account, AuthInfo, AccountType } from './AuthTypes';
import { AccountFactory } from './AccountFactory';
import { OfflineAccount } from './OfflineAccount';
import { FileUtils } from '../util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-AccountService';
const CURRENT_FILE = 'fcl_current_account.json';

/** 当前账号选择记录 (持久化格式) */
interface CurrentAccountRef {
  identifier: string;
}

/** 启动所需的认证参数 */
export interface LaunchAuth {
  username: string;
  uuid: string;
  accessToken: string;
  userType: string;
}

export class AccountService {
  private static instance: AccountService | null = null;

  private constructor() {
  }

  static getInstance(): AccountService {
    if (!AccountService.instance) {
      AccountService.instance = new AccountService();
    }
    return AccountService.instance;
  }

  /** 读取所有账号 */
  listAccounts(): Account[] {
    return AccountFactory.loadAll();
  }

  /**
   * 获取当前选中账号
   * 未显式选择时: 取已存账号的第一个；若一个都没有则回退到默认离线账号 Player
   */
  getCurrentAccount(): Account {
    const accounts = this.listAccounts();
    const selectedId = this.getSelectedIdentifier();

    if (selectedId.length > 0) {
      const found = accounts.find(a => a.identifier === selectedId);
      if (found) {
        return found;
      }
    }
    if (accounts.length > 0) {
      return accounts[0];
    }
    return new OfflineAccount({ username: 'Player' });
  }

  /** 设置当前选中账号 */
  setCurrentAccount(identifier: string): boolean {
    const path = `${AppContext.filesDir}/${CURRENT_FILE}`;
    const ref: CurrentAccountRef = { identifier: identifier };
    return FileUtils.writeJSON(path, ref);
  }

  private getSelectedIdentifier(): string {
    const path = `${AppContext.filesDir}/${CURRENT_FILE}`;
    const data = FileUtils.readJSON<Record<string, Object>>(path);
    if (!data) {
      return '';
    }
    return data['identifier'] as string ?? '';
  }

  /**
   * 取得当前账号的启动认证参数
   *
   * 在线账号走 logIn()（微软/Yggdrasil 会做真实鉴权）；
   * 离线账号走 playOffline()，UUID 由 MD5("OfflinePlayer:" + name) 得出（与官方一致）。
   */
  async getLaunchAuth(): Promise<LaunchAuth> {
    const account = this.getCurrentAccount();
    try {
      let info: AuthInfo;
      if (account.type === AccountType.OFFLINE) {
        info = await account.playOffline();
      } else {
        info = await account.logIn();
        if (!info.isValid()) {
          throw new Error('Account credentials are invalid');
        }
      }
      return {
        username: info.username,
        uuid: info.uuid,
        accessToken: info.accessToken,
        userType: info.userType
      };
    } catch (err) {
      hilog.warn(0x0000, TAG, `Online login failed, fallback to offline: ${err}`);
      const offline = new OfflineAccount({ username: account.username || 'Player' });
      const info = await offline.playOffline();
      return {
        username: info.username,
        uuid: info.uuid,
        accessToken: info.accessToken,
        userType: info.userType
      };
    }
  }
}
