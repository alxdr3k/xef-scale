# Local Dev Server

로컬 개발 서버를 관리합니다.

## Arguments

$ARGUMENTS: start | stop | restart | status (기본값: status)

## Commands

### status (기본값)

서버 상태를 확인합니다:

```bash
echo "=== Rails Server ==="
pgrep -f "puma.*xef-scale" > /dev/null && echo "Running (PID: $(pgrep -f 'puma.*xef-scale'))" || echo "Stopped"

echo -e "\n=== Solid Queue ==="
pgrep -f "solid_queue:start" > /dev/null && echo "Running (PID: $(pgrep -f 'solid_queue:start'))" || echo "Stopped"
```

### stop

모든 서버 프로세스를 종료합니다:

```bash
pkill -f "puma.*xef-scale" 2>/dev/null && echo "Rails server stopped" || echo "Rails server not running"
pkill -f "solid_queue:start" 2>/dev/null && echo "Solid Queue stopped" || echo "Solid Queue not running"
```

### start

Rails 서버와 Solid Queue를 시작합니다:

1. 먼저 기존 프로세스 확인 후 중복 시작 방지
2. 백그라운드에서 각각 시작:
   - `doppler run -- bin/rails server`
   - `doppler run -- bin/rails solid_queue:start`
3. 5초 후 상태 확인

### restart

stop 후 start를 실행합니다.

## Notes

- `bin/dev`는 stdin 문제로 백그라운드 실행 불가, 별도 프로세스로 시작
- 서버: http://localhost:3000
- Doppler 환경변수 필요
