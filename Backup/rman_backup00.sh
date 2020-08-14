set echo on
connect target /
configure retention policy to recovery window of 7 days;
configure controlfile autobackup on;
configure controlfile autobackup format for device type disk to '/rman_backup/CMSDB_RMANBACKUP/AutoBackup_Control_%F.ctl';

run
{
  sql "alter session set NLS_DATE_FORMAT=''YYYY/MM/DD HH24:MI:SS''";
  allocate channel dch1 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_FULL_%U.bak';
  allocate channel dch2 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_FULL_%U.bak';
  allocate channel dch3 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_FULL_%U.bak';
  allocate channel dch4 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_FULL_%U.bak';

  crosscheck backup;
  delete noprompt expired backup;

  report obsolete;
  delete noprompt obsolete;

  sql 'alter system archive log current';

  backup tag = 'CMSDB_RMAN_BACKUP00'
  incremental level 0
  database
  include current controlfile;

  sql 'alter system archive log current';

  crosscheck archivelog all;
  delete noprompt expired backup of archivelog all;

  backup tag = 'ARCHIVE'
  format '/rman_backup/CMSDB_RMANBACKUP/ARCH_RMAN_%U.bak' (archivelog all not backed up);
  delete noprompt archivelog until time 'sysdate-2';

  release channel dch1;
  release channel dch2;
  release channel dch3;
  release channel dch4;
}
