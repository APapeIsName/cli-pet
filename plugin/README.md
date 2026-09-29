# cli-pet Claude Code 플러그인

Claude Code가 하는 일(생각 중, 파일 읽기·수정, 명령 실행, 권한 요청, 완료)을 CLIPet 데스크톱 펫이 말풍선으로 보여줍니다.

- CLIPet 앱이 설치돼 있어야 합니다 (Homebrew, curl 한 줄 설치, 직접 설치 모두 자동으로 찾습니다). 설치 방법은 저장소 루트의 README를 보세요.
- 앱이 없으면 플러그인은 아무 일도 하지 않습니다.
- 세션이 시작될 때 펫이 떠 있지 않으면 자동으로 띄웁니다. 끄려면 환경 변수 `CLI_PET_NO_AUTOSTART=1`을 설정하세요.
- 앱을 다른 곳에 두었다면 `CLI_PET_APP=/경로/CLIPet.app`을 설정하세요.
