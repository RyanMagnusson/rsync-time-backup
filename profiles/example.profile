# Rules use rsync filter syntax and are relative to the backup source.
version 1
include /Documents/***
include /.ssh/***
exclude /.ssh/known_hosts
exclude /.cache/***
