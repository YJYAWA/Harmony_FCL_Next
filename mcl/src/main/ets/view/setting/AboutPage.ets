/**
 * 关于/帮助页面
 * 移植自: FCL/ui/setting/AboutPage + HelpPage
 */
@ComponentV2
export struct AboutPage {
  @Local appVersion: string = '1.0.0';
  @Local buildDate: string = '2026-07-24';
  @Local deviceInfo: string = 'HarmonyOS NEXT';

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // Logo 和标题
          Column() {
            Text('FCL').fontSize(48).fontWeight(FontWeight.Bold).fontColor('#E94560')
            Text('Fold Craft Launcher').fontSize(20).fontColor('#FFFFFF').margin({ top: 4 })
            Text('for HarmonyOS NEXT').fontSize(14).fontColor('#999999').margin({ top: 2 })
            Text(`Version ${this.appVersion}`).fontSize(12).fontColor('#666666').margin({ top: 4 })
          }
          .width('100%').padding({ top: 32, bottom: 24 })
          .alignItems(HorizontalAlign.Center)

          // 开源协议
          this.buildSection('License');
          Column() {
            Text('This project is licensed under GPL-3.0').fontSize(13).fontColor('#CCCCCC')
            Text('Based on these open source projects:').fontSize(12).fontColor('#999999').margin({ top: 8 })
            this.buildCreditItem('HMCL', 'Hello Minecraft! Launcher', 'https://github.com/HMCL-dev/HMCL')
            this.buildCreditItem('PojavLauncher', 'Minecraft Java on Android', 'https://github.com/PojavLauncherTeam/PojavLauncher')
            this.buildCreditItem('AMCL', 'Axe Minecraft Launcher for HarmonyOS', 'https://github.com/LZZLHY/amcl')
            this.buildCreditItem('MobileGlues', 'GL → GLES Translation Layer', 'https://github.com/MobileGL-Dev/MobileGlues-release')
            this.buildCreditItem('OpenJDK', 'Java Runtime for HarmonyOS', 'https://github.com/LZZLHY/mc-ohos-resources')
          }
          .width('100%').padding(14).backgroundColor('#16213E').borderRadius(10)
          .margin({ bottom: 16 })

          // 帮助
          this.buildSection('Help');
          Column() {
            this.buildHelpItem('Getting Started', 'How to set up and launch Minecraft')
            this.buildHelpItem('Microsoft Login', 'How to log in with your Microsoft account')
            this.buildHelpItem('Installing Mods', 'How to install Fabric, Forge, and mods')
            this.buildHelpItem('Touch Controls', 'How to customize on-screen controls')
            this.buildHelpItem('Troubleshooting', 'Common issues and solutions')
          }
          .width('100%').padding(14).backgroundColor('#16213E').borderRadius(10)
          .margin({ bottom: 16 })

          // 贡献者
          this.buildSection('Credits');
          Text('FCL-Team & Community Contributors')
            .fontSize(13).fontColor('#CCCCCC')
            .width('100%').padding(14).backgroundColor('#16213E').borderRadius(10)

          // 底部
          Text('"Minecraft" is a trademark of Mojang Studios.\nFCL is not affiliated with Mojang, Microsoft, or Huawei.')
            .fontSize(11).fontColor('#555555').textAlign(TextAlign.Center)
            .margin({ top: 24, bottom: 32 }).padding({ left: 16, right: 16 })
        }
        .width('100%').padding(16)
      }
      .width('100%').height('100%').backgroundColor('#1A1A2E')
    }
    .title('About FCL')
  }

  @Builder
  buildSection(title: string) {
    Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E94560')
      .width('100%').margin({ top: 8, bottom: 10 })
  }

  @Builder
  buildCreditItem(name: string, desc: string, url: string) {
    Row() {
      Column() {
        Text(name).fontSize(13).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
        Text(desc).fontSize(11).fontColor('#999999').margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(url).fontSize(10).fontColor('#666666').maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width(80)
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  buildHelpItem(title: string, desc: string) {
    Row() {
      Text('📖').fontSize(16).margin({ right: 10 })
      Column() {
        Text(title).fontSize(14).fontColor('#FFFFFF')
        Text(desc).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(18).fontColor('#555555')
    }
    .width('100%').padding({ top: 8, bottom: 8 })
  }
}
