#!/usr/bin/env bash

AUDIO_PATH="/path/to/music/rain_sounds.mp3"
ALARM_PATH="/path/to/music/alarm.mp3"

WORK_MIN=25
BREAK_MIN=5

AUDIO_PATH="/path/to/your/rain_sounds.mp3"
ALARM_PATH="/path/to/your/alarm.mp3"

WORK_MIN=50
BREAK_MIN=10
SETS=5
ALARM_DURATION=15

# Global process PIDs
AUDIO_PID=""
ALARM_PID=""

stop_music() {
    if [[ -n "$AUDIO_PID" ]]; then
        kill "$AUDIO_PID" 2>/dev/null
        wait "$AUDIO_PID" 2>/dev/null
        AUDIO_PID=""
    fi
}

pause_music() {
    if [[ -n "$AUDIO_PID" ]]; then
        kill -STOP "$AUDIO_PID" 2>/dev/null
    fi
}

resume_music() {
    if [[ -n "$AUDIO_PID" ]]; then
        kill -CONT "$AUDIO_PID" 2>/dev/null
    fi
}

stop_alarm() {
    if [[ -n "$ALARM_PID" ]]; then
        kill "$ALARM_PID" 2>/dev/null
        wait "$ALARM_PID" 2>/dev/null
        ALARM_PID=""
    fi
}

cleanup() {
    stop_music
    stop_alarm
    tput cnorm # restore cursor
    printf "\n"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

start_music() {
    stop_music
    mpv --no-video --loop=inf "$AUDIO_PATH" >/dev/null 2>&1 &
    AUDIO_PID=$!
}

trigger_alarm() {
    stop_alarm
    if [[ -f "$ALARM_PATH" ]]; then
        mpv --no-video --loop=inf "$ALARM_PATH" >/dev/null 2>&1 &
        ALARM_PID=$!
    fi

    for ((sec=ALARM_DURATION; sec>0; sec--)); do
        printf "\r🔔 ALARM! Ending in %02ds... Press [c] to silence alarm " "$sec"
        [[ ! -f "$ALARM_PATH" ]] && printf "\a"

        if read -r -s -t 1 -n 1 key; then
            case "$key" in
                c|C)
                    break
                    ;;
                q|Q)
                    cleanup
                    ;;
            esac
        fi
    done

    stop_alarm
    printf "\r%-65s\r" ""
}

# Run a countdown phase. Returns:
# 0 = normal completion
# 1 = quit ('q')
# 2 = reset current set ('r')
# 3 = reset all sets ('a')
countdown() {
    local duration=$1
    local mode=$2
    local set_idx=$3
    local remaining=$duration

    while (( remaining > 0 )); do
        printf "\r[Set %d/%d] %-5s: %02d:%02d  [p:pause | q:quit | r:reset set | a:reset all] " \
            "$set_idx" "$SETS" "$mode" "$((remaining/60))" "$((remaining%60))"

        # Read 1 keypress with a 1-second timeout
        if read -r -s -t 1 -n 1 key; then
            case "$key" in
                p|P)
                    pause_music
                    while true; do
                        printf "\r[Set %d/%d] %-5s: %02d:%02d  [PAUSED - Press 'p' to resume | q:quit] " \
                            "$set_idx" "$SETS" "$mode" "$((remaining/60))" "$((remaining%60))"
                        
                        if read -r -s -n 1 pause_key; then
                            case "$pause_key" in
                                p|P)
                                    resume_music
                                    break
                                    ;;
                                q|Q)
                                    return 1
                                    ;;
                            esac
                        fi
                    done
                    ;;
                q|Q)
                    return 1
                    ;;
                r|R)
                    return 2
                    ;;
                a|A)
                    return 3
                    ;;
            esac
        else
            ((remaining--))
        fi
    done

    printf "\n"
    return 0
}

# Hide cursor
tput civis

current_set=1

while (( current_set <= SETS )); do
    # 1. Work Session
    start_music
    countdown $((WORK_MIN * 60)) "WORK" "$current_set"
    res=$?

    if (( res == 1 )); then
        break
    elif (( res == 2 )); then
        stop_music
        continue
    elif (( res == 3 )); then
        stop_music
        current_set=1
        continue
    fi

    stop_music
    trigger_alarm

    # 2. Break Session
    countdown $((BREAK_MIN * 60)) "BREAK" "$current_set"
    res=$?

    if (( res == 1 )); then
        break
    elif (( res == 2 )); then
        continue
    elif (( res == 3 )); then
        current_set=1
        continue
    fi

    trigger_alarm

    ((current_set++))
done

if (( current_set > SETS )); then
    printf "\nAll %d sets completed!\n" "$SETS"
fi

