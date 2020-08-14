set echo on
connect target /
configure controlfile autobackup on;
configure controlfile autobackup format for device type disk to '/rman_backup/CMSDB_RMANBACKUP/AutoBackup_Control_%F.ctl';

run
{
  sql "alter session set NLS_DATE_FORMAT=''YYYY/MM/DD HH24:MI:SS''";
  allocate channel dch1 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_incre01_%U.bak';
  allocate channel dch2 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_incre01_%U.bak';
  allocate channel dch3 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_incre01_%U.bak';
  allocate channel dch4 device type disk format '/rman_backup/CMSDB_RMANBACKUP/CMSDB_incre01_%U.bak';

  crosscheck backup;
  delete noprompt expired backup;

  report obsolete;
  delete noprompt obsolete;

  sql 'alter system archive log current';

  backup tag = 'CMSDB_RMAN_BACKUP01'
  incremental level 1
  database
  include current controlfile;

  sql 'alter system archive log current';

  crosscheck archivelog all;
  delete noprompt expired backup of archivelog all;

  backup tag = 'ARCHIVE'
  format '/rman_backup/CMSDB_RMANBACKUP/ARCH_RMAN_%U.bak' (archivelog all not backed up);
  delete noprompt archivelog all backed up 1 times to device type disk;

  release channel dch1;
  release channel dch2;
  release channel dch3;
  release channel dch4;
}
