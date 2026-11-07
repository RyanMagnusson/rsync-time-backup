./rsync_tmbackup.sh \
    --id_rsa ~/.ssh/id_rasppi  \
    --no-auto-expire \
    --rsync-append-flags "--no-perms --no-group --no-specials --no-devices --bwlimit=10000" \
    --exclude-from ~/.config/rsync_timemachine/excluded.config \
    ~/ ryanmagnusson@192.168.1.72:/Volumes/SeagateVusion/backup/MAC-D0234KP65N