# 권리자 문의 가이드

문의할 대상 목록은 `packs.csv`에서 **판정 = 문의**인 줄이에요. `문의 기대`(높음, 보통, 낮음) 순서로 보내면 돼요. 보낸 날짜와 받은 답은 같은 줄의 `문의일`, `답변` 칸에 적어 주세요.

## 지킬 것

- **허락은 반드시 글로 받는다.** 메일 답장이나 공식 문서가 있어야 해요. 전화나 DM으로 받은 말은 나중에 증명하기 어려워요.
- **답이 없으면 허락이 아니다.** 한 번 보내고 답이 없으면 불가로 둬요.
- **범위를 구체적으로 묻는다.** 아래 세 가지를 각각 허락받아야 팩을 만들 수 있어요.
  1. 직접 새로 그린 스프라이트여도 되는지 (수정)
  2. 공개 저장소(GitHub)와 무료 앱에 넣어 배포해도 되는지 (재배포)
  3. 원하는 표기 문구가 무엇인지
- **허락받은 조건은 팩의 `LICENSE`에 그대로 옮긴다.** 받은 메일은 따로 보관해요.
- 닌텐도, 포켓몬, 쿠마몬처럼 **개별 허락을 하지 않는다고 밝힌 곳은 보내지 않는다** (CSV의 판정 = 불가).

## 메일 제목

- 한국어: `[비상업 문의] 무료 오픈소스 데스크톱 펫 앱에 ○○ 캐릭터 사용 가능 여부`
- English: `Permission request: non-commercial use of ○○ in a free open-source desktop pet app`
- 日本語: `【非営利利用のご相談】無料オープンソースのデスクトップペットアプリでの「○○」の使用について`

## 본문 — 한국어

```
안녕하세요. 개인 개발자 ○○○입니다.

macOS용 무료 오픈소스 데스크톱 펫 앱 "CLIPet"을 만들고 있습니다.
작은 캐릭터가 터미널 화면 위에 떠 있다가 클릭하면 반응하고, 작업 상태를 말풍선으로 알려주는 앱입니다.
(화면 예시 첨부)

이 앱에서 사용자가 고를 수 있는 캐릭터로 "○○"를 넣고 싶어 문의드립니다.

- 사용 방식: 공식 이미지를 그대로 쓰지 않고, 직접 새로 그린 작은 스프라이트(표정 5~9장)를 사용합니다.
- 배포: GitHub 공개 저장소와 무료 앱으로만 배포합니다. 판매, 광고, 후원, 유료 기능은 없습니다.
- 표기: 앱과 저장소에 권리자 표기와 "비공식이며 ○○과 관련이 없습니다"라는 문구를 넣습니다. 로고와 상표는 쓰지 않습니다.
- 요청 시: 언제든 즉시 삭제하겠습니다.

위 조건으로 사용해도 괜찮을지, 괜찮다면 원하시는 표기 문구나 추가 조건이 있는지 알려주시면 감사하겠습니다.
어렵다면 그렇게만 알려주셔도 됩니다.

감사합니다.
○○○ 드림
(연락처 / 저장소 주소)
```

## 본문 — English

```
Hello,

I'm an independent developer building "CLIPet", a free, open-source desktop pet app for macOS.
A small character floats above the terminal, reacts when clicked, and shows short status messages in a speech bubble.
(Screenshot attached.)

I'd like to ask whether I may include "○○" as one of the characters users can choose.

- How: I would not use official artwork as-is. I would draw my own small sprites (5–9 expressions).
- Distribution: only via a public GitHub repository and the free app. No sales, ads, donations or paid features.
- Credit: the app and repository would carry your copyright notice and a line stating it is unofficial and not affiliated with or endorsed by you. No logos or trademarks.
- On request: I will remove it immediately at any time.

Could you let me know whether this use is acceptable, and if so, the credit line or any conditions you'd like?
A simple "no" is perfectly fine too.

Thank you for your time.
○○○
(contact / repository URL)
```

## 本文 — 日本語

```
はじめまして。個人開発者の○○○と申します。

macOS向けの無料・オープンソースのデスクトップペットアプリ「CLIPet」を開発しております。
小さなキャラクターがターミナル画面の上に浮かび、クリックすると反応し、作業の状況を吹き出しで知らせるアプリです。
（画面例を添付いたします）

このアプリで利用者が選べるキャラクターとして「○○」を使わせていただけないか、ご相談させてください。

- 使用方法：公式画像をそのまま使わず、自分で新たに描いた小さなスプライト（表情5〜9枚）を使用します。
- 配布：GitHubの公開リポジトリと無料アプリのみで配布します。販売・広告・寄付・有料機能はありません。
- 表記：アプリとリポジトリに権利者表記と「非公式であり、○○とは関係ありません」という文言を入れます。ロゴや商標は使用しません。
- ご要望があれば：いつでも直ちに削除いたします。

上記の条件で使用してもよろしいか、また可能な場合はご希望の表記や追加条件があればお教えいただけますと幸いです。
難しい場合はその旨だけでもお知らせいただければ十分です。

お忙しいところ恐れ入りますが、よろしくお願いいたします。
○○○
（連絡先／リポジトリURL）
```

## 문의처 찾는 법

CSV의 `문의처` 칸에 적힌 곳은 조사 과정에서 확인한 창구예요. 메일 주소가 적혀 있지 않은 곳은 그 회사 공식 사이트의 **라이선스, 제휴, IP 사업, 고객센터** 메뉴에서 찾으면 돼요. 조사 중에 확인하지 못한 주소는 일부러 적지 않았어요.
