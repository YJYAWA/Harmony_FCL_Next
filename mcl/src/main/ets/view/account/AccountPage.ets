/**
 * 账号管理页面
 * 移植自: FCL/ui/account/
 * 支持 Microsoft 正版登录、离线账号创建/切换/删除
 */
import { MicrosoftAccount } from '../../core/auth/MicrosoftAccount';
import { OfflineAccount } from '../../core/auth/OfflineAccount';
import { Account, AccountType, AuthInfo } from '../../core/auth/AuthTypes';
import { FileUtils } from '../../core/util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { promptAction } from '@kit.ArkUI';

const ACCOUNTS_FILE = 'fcl_accounts.json';

/** 选中账号索引的持久化结构 */
interface SavedIndex {
  index: number;
}

@ComponentV2
export struct AccountPage {
  @Local accounts: Account[] = [];
  @Local selectedAccountIndex: number = -1;
  @Local isLoading: boolean = false;
  @Local statusMessage: string = '';
  @Local showAddDialog: boolean = false;
  @Local showLoginStatus: string = '';

  aboutToAppear(): void {
    this.loadAccounts();
  }

  async loadAccounts(): Promise<void> {
    const path = `${AppContext.filesDir}/${ACCOUNTS_FILE}`;
    const data = FileUtils.readJSON<Array<Record<string, Object>>>(path);

    if (!data) {
      this.accounts = [];
      return;
    }

    this.accounts = data.map(item => {
      const type = item['type'] as AccountType;
      if (type === AccountType.OFFLINE) {
        return OfflineAccount.fromStorage(item);
      } else if (type === AccountType.MICROSOFT) {
        return MicrosoftAccount.fromStorage(item);
      }
      return OfflineAccount.fromStorage(item);
    });

    // 恢复选中状态
    const selectedPath = `${AppContext.filesDir}/fcl_selected_account.json`;
    const selected = FileUtils.readJSON<SavedIndex>(selectedPath);
    if (selected && selected.index >= 0 && selected.index < this.accounts.length) {
      this.selectedAccountIndex = selected.index;
    }
  }

  async saveAccounts(): Promise<void> {
    const path = `${AppContext.filesDir}/${ACCOUNTS_FILE}`;
    const data = this.accounts.map(a => a.toStorage());
    FileUtils.writeJSON(path, data);

    // 保存选中状态
    const selectedPath = `${AppContext.filesDir}/fcl_selected_account.json`;
    const saved: SavedIndex = { index: this.selectedAccountIndex };
    FileUtils.writeJSON(selectedPath, saved);
  }

  build() {
    Stack() {
      Column() {
        // 标题
        Row() {
          Text('Account Management')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')

          Blank()

          Button('+ Add')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#E94560')
            .borderRadius(8)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.showAddDialog = true; })
        }
        .width('100%')
        .padding(16)

        // 选中账号信息
        if (this.selectedAccountIndex >= 0 && this.selectedAccountIndex < this.accounts.length) {
          this.buildSelectedAccount();
        }

        // 账号列表
        Scroll() {
          Column() {
            ForEach(this.accounts, (account: Account, index: number) => {
              this.buildAccountCard(account, index);
            })

            if (this.accounts.length === 0) {
              this.buildEmptyState();
            }
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#1A1A2E')

      // 添加账号对话框
      if (this.showAddDialog) {
        this.buildAddAccountDialog();
      }

      // 登录状态
      if (this.showLoginStatus) {
        this.buildLoginOverlay();
      }
    }
  }

  @Builder
  buildSelectedAccount() {
    Column() {
      Text('Selected Account')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ bottom: 4 })

      Text(`${this.accounts[this.selectedAccountIndex].character}`)
        .fontSize(18)
        .fontColor('#4CAF50')
        .fontWeight(FontWeight.Medium)

      Text(`${this.accounts[this.selectedAccountIndex].type} · ${this.accounts[this.selectedAccountIndex].uuid}`)
        .fontSize(12)
        .fontColor('#666666')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#16213E')
    .borderRadius(8)
    .margin({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  buildAccountCard(account: Account, index: number) {
    Row() {
      Column() {
        Row() {
          Text(account.character)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedAccountIndex === index ? '#4CAF50' : '#FFFFFF')

          if (this.selectedAccountIndex === index) {
            Text(' ✓')
              .fontSize(14)
              .fontColor('#4CAF50')
          }
        }

        Text(`${account.type} · ${account.uuid.substring(0, 8)}...`)
          .fontSize(12)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      // 选择按钮
      Button(this.selectedAccountIndex === index ? 'Selected' : 'Select')
        .fontSize(12)
        .fontColor(this.selectedAccountIndex === index ? '#4CAF50' : '#FFFFFF')
        .backgroundColor(this.selectedAccountIndex === index ? 'rgba(76,175,80,0.15)' : '#0F3460')
        .borderRadius(6)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.selectedAccountIndex = index;
          this.saveAccounts();
        })

      // Microsoft 账号的刷新登录按钮
      if (account.type === AccountType.MICROSOFT) {
        Button('Login')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#1E88E5')
          .borderRadius(6)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .margin({ left: 6 })
          .onClick(() => this.microsoftLogin(account as Object as MicrosoftAccount))
      }

      // 删除按钮
      Button('Delete')
        .fontSize(12)
        .fontColor('#FF5252')
        .backgroundColor('transparent')
        .border({ width: 1, color: '#FF5252' })
        .borderRadius(6)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => {
          this.accounts.splice(index, 1);
          if (this.selectedAccountIndex === index) {
            this.selectedAccountIndex = -1;
          } else if (this.selectedAccountIndex > index) {
            this.selectedAccountIndex--;
          }
          this.saveAccounts();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#16213E')
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text('No accounts')
        .fontSize(18)
        .fontColor('#999999')
        .margin({ top: 64, bottom: 8 })

      Text('Add a Microsoft or offline account to get started')
        .fontSize(14)
        .fontColor('#666666')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // 添加账号对话框
  @Builder
  buildAddAccountDialog() {
    Column() {
      Column() {
        Text('Add Account')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ bottom: 16 })

        // Microsoft 登录
        Button('Microsoft Login')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#1E88E5')
          .borderRadius(8)
          .padding(16)
          .width('100%')
          .margin({ bottom: 12 })
          .onClick(() => {
            this.showAddDialog = false;
            this.addMicrosoftAccount();
          })

        // 离线账号
        this.buildOfflineAccountForm();

        // 取消
        Button('Cancel')
          .fontSize(14)
          .fontColor('#999999')
          .backgroundColor('transparent')
          .margin({ top: 8 })
          .onClick(() => { this.showAddDialog = false; })
      }
      .padding(24)
      .backgroundColor('#16213E')
      .borderRadius(16)
      .width('85%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showAddDialog = false; })
  }

  @Builder
  buildOfflineAccountForm() {
    Column() {
      Text('Offline Account')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ bottom: 8 })

      TextInput({ placeholder: 'Enter player name...' })
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(8)
        .padding(12)
        .width('100%')
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          // 存储到临时变量
          AppStorage.setOrCreate('tempOfflineName', value);
        })

      Button('Create Offline Account')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F3460')
        .borderRadius(8)
        .padding(12)
        .width('100%')
        .onClick(() => {
          const name = AppStorage.get<string>('tempOfflineName') ?? 'Player';
          const account = new OfflineAccount({ username: name });
          this.accounts.push(account);
          this.saveAccounts();
          this.showAddDialog = false;
        })
    }
    .width('100%')
  }

  // 登录进度覆盖层
  @Builder
  buildLoginOverlay() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#E94560')

      Text(this.showLoginStatus)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .margin({ top: 16, left: 32, right: 32 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.85)')
  }

  // ========== 操作方法 ==========

  async addMicrosoftAccount(): Promise<void> {
    const account = new MicrosoftAccount();
    this.showLoginStatus = 'Starting Microsoft login...';

    account.statusCallback = (status: string) => {
      this.showLoginStatus = status;
    };

    try {
      const authInfo = await account.logIn();
      this.accounts.push(account);
      this.selectedAccountIndex = this.accounts.length - 1;
      await this.saveAccounts();
      this.showLoginStatus = '';
      promptAction.showToast({ message: `Logged in as ${authInfo.displayName}` });
    } catch (err) {
      this.showLoginStatus = '';
      const msg = err instanceof Error ? err.message : String(err);
      promptAction.showToast({ message: `Login failed: ${msg}` });
    }
  }

  async microsoftLogin(account: MicrosoftAccount): Promise<void> {
    this.showLoginStatus = 'Refreshing Microsoft login...';
    account.statusCallback = (status: string) => {
      this.showLoginStatus = status;
    };

    try {
      await account.logIn();
      await this.saveAccounts();
      this.showLoginStatus = '';
      promptAction.showToast({ message: 'Login refreshed' });
    } catch (err) {
      this.showLoginStatus = '';
      const msg = err instanceof Error ? err.message : String(err);
      promptAction.showToast({ message: `Login failed: ${msg}` });
    }
  }
}
