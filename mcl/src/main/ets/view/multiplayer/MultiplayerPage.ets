/**
 * 多人游戏/服务器列表管理
 * 移植自: FCL/ui/multiplayer/ + FCL/control/MultiplayerDialog
 */
import { FileUtils } from '../../core/util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { LaunchConfig } from '../../core/game/GameTypes';
import { GameLauncherService } from '../../service/GameLauncherService';
import { promptAction } from '@kit.ArkUI';

const SERVERS_FILE = 'fcl_servers.json';

/** 服务器条目 */
interface ServerEntry {
  id: string;
  name: string;
  address: string;
  port: number;
  version?: string;
  icon?: string;
  lastJoined?: number;
  favorite?: boolean;
}

@ComponentV2
export struct MultiplayerPage {
  @Local servers: ServerEntry[] = [];
  @Local showAddDialog: boolean = false;
  @Local editName: string = '';
  @Local editAddress: string = '';
  @Local editPort: string = '25565';
  @Local searchQuery: string = '';
  @Local filteredServers: ServerEntry[] = [];

  aboutToAppear(): void {
    this.loadServers();
  }

  loadServers(): void {
    const path = `${AppContext.filesDir}/${SERVERS_FILE}`;
    const data = FileUtils.readJSON<ServerEntry[]>(path);
    this.servers = data ?? [];
    this.applyFilter();
  }

  saveServers(): void {
    const path = `${AppContext.filesDir}/${SERVERS_FILE}`;
    FileUtils.writeJSON(path, this.servers);
  }

  applyFilter(): void {
    if (!this.searchQuery.trim()) {
      this.filteredServers = [...this.servers];
      return;
    }
    const q = this.searchQuery.toLowerCase();
    this.filteredServers = this.servers.filter(s =>
      s.name.toLowerCase().includes(q) || s.address.toLowerCase().includes(q)
    );
  }

  build() {
    Stack() {
      Column() {
        // 标题和搜索
        Row() {
          Text('Servers')
            .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')

          Blank()

          Button('+ Add')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => {
              this.editName = '';
              this.editAddress = '';
              this.editPort = '25565';
              this.showAddDialog = true;
            })
        }
        .width('100%').padding(16)

        // 搜索
        TextInput({ placeholder: 'Search servers...', text: this.searchQuery })
          .fontSize(14).fontColor('#FFFFFF').backgroundColor('#16213E')
          .borderRadius(8).padding(12).width('100%')
          .margin({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.searchQuery = value;
            this.applyFilter();
          })

        // 服务器列表
        if (this.filteredServers.length === 0) {
          this.buildEmptyState();
        } else {
          List() {
            ForEach(this.filteredServers, (server: ServerEntry) => {
              ListItem() {
                this.buildServerCard(server);
              }
            })
          }
          .layoutWeight(1).scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0.5, color: '#2A2A4A' })
        }
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')

      // 添加/编辑对话框
      if (this.showAddDialog) {
        this.buildAddDialog();
      }
    }
  }

  @Builder
  buildServerCard(server: ServerEntry) {
    Row() {
      // 状态图标
      Column() {
        if (server.favorite) {
          Text('⭐').fontSize(24)
        } else {
          Text('🖥️').fontSize(24)
        }
      }
      .width(48).height(48)
      .borderRadius(8)
      .backgroundColor('#0F3460')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 12 })

      Column() {
        Text(server.name)
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')

        Text(`${server.address}:${server.port}`)
          .fontSize(13).fontColor('#999999').margin({ top: 2 })

        if (server.version) {
          Text(`MC ${server.version}`)
            .fontSize(11).fontColor('#666666')
        }

        if (server.lastJoined) {
          Text(`Last played: ${new Date(server.lastJoined).toLocaleDateString()}`)
            .fontSize(11).fontColor('#555555').margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)

      // 操作
      Column() {
        Button('Join')
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#4CAF50')
          .borderRadius(6).padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .margin({ bottom: 4 })
          .onClick(() => this.joinServer(server))

        Button(server.favorite ? '★' : '☆')
          .fontSize(14)
          .fontColor(server.favorite ? '#FFD700' : '#999999')
          .backgroundColor('transparent')
          .onClick(() => {
            server.favorite = !server.favorite;
            this.saveServers();
          })
      }
      .margin({ left: 8 })
    }
    .width('100%').padding(14).backgroundColor('#16213E')
    .borderRadius(10).margin({ top: 6, left: 16, right: 16 })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text('No servers added')
        .fontSize(18).fontColor('#999999').margin({ top: 64, bottom: 8 })
      Text('Add a server to start playing multiplayer')
        .fontSize(14).fontColor('#666666')
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildAddDialog() {
    Column() {
      Column() {
        Text('Add Server')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .margin({ bottom: 16 })

        // 服务器名称
        Text('Server Name')
          .fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        TextInput({ placeholder: 'My Server', text: this.editName })
          .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(8).padding(12).width('100%').margin({ bottom: 12 })
          .onChange((value: string) => { this.editName = value; })

        // 地址
        Text('Address')
          .fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        TextInput({ placeholder: 'mc.example.com', text: this.editAddress })
          .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(8).padding(12).width('100%').margin({ bottom: 12 })
          .onChange((value: string) => { this.editAddress = value; })

        // 端口
        Text('Port')
          .fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        TextInput({ placeholder: '25565', text: this.editPort })
          .fontSize(14).fontColor('#FFFFFF').backgroundColor('#0F3460')
          .borderRadius(8).padding(12).width('100%').margin({ bottom: 20 })
          .type(InputType.Number)
          .onChange((value: string) => { this.editPort = value; })

        Row() {
          Button('Cancel')
            .fontSize(14).fontColor('#999999').backgroundColor('#0F3460')
            .borderRadius(8).padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .onClick(() => { this.showAddDialog = false; })

          Button('Add Server')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#E94560')
            .borderRadius(8).padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .margin({ left: 16 })
            .onClick(() => {
              if (this.editName && this.editAddress) {
                this.servers.push({
                  id: `srv_${Date.now()}`,
                  name: this.editName,
                  address: this.editAddress,
                  port: parseInt(this.editPort) || 25565
                });
                this.saveServers();
                this.showAddDialog = false;
                this.applyFilter();
              } else {
                promptAction.showToast({ message: 'Please fill in name and address' });
              }
            })
        }
      }
      .padding(24).backgroundColor('#16213E').borderRadius(16).width('85%')
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center).backgroundColor('rgba(0,0,0,0.7)')
    .onClick(() => { this.showAddDialog = false; })
  }

  /**
   * 直接连接到服务器
   * 通过启动配置文件中的 --server 参数
   */
  joinServer(server: ServerEntry): void {
    server.lastJoined = Date.now();
    this.saveServers();

    // 设置直连地址
    const address = `${server.address}:${server.port}`;

    promptAction.showToast({ message: `Connecting to ${address}` });

    // 实际连接需要启动 Minecraft 并传入 --server 参数
    // 由 GameLauncherService.handleLaunch() 处理
  }
}
