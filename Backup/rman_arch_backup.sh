set echo on
connect target /
run {
  configure retention policy to recovery window of 7 days;
  configure controlfile autobackup on;
  configure controlfile autobackup format for device type disk to '/rman_backup/CMSDB_RMANBACKUP/AutoBackup_Control_%F.ctl';

  report obsolete;
  delete noprompt obsolete;

  crosscheck backup of controlfile;
  delete noprompt expired backup of controlfile;

  crosscheck backup of archivelog all;
  delete noprompt expired backup of archivelog all;
  delete noprompt archivelog until time 'sysdate-2';

  backup tag 'ARCHIVE'
  format '/rman_backup/CMSDB_RMANBACKUP/ARCH_RMAN_%U.bak' (archivelog all not backed up);
}
