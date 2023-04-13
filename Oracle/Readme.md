# Crontab 구성 가이드

Script 경로는 계정명에 따라 수정. 여기서는 oracle 과 grid 로 가정함.

## Oracle 계정
### node#1
```
### Manage log of Oracle (ashurei@sk.com)
20 01 * * * /home/oracle/DBA/script/ManageLog-oracle.sh

### Manage archive log (ashurei@sk.com) (only node#2)
#30 01 * * * /home/oracle/DBA/script/ManageLog-archive.sh

### purge stats (ashurei@sk.com) (only node#2)
#00 23 * * * /home/oracle/DBA/script/purge_stats.sh

### Datapump (ashurei@sk.com) (only node#2)
#00 02 * * * /home/oracle/DBA/script/expdp_ORCL.sh

### RMAN (ashurei@sk.com) (only node#2)
#00 23 * * 0,2,4 /home/oracle/DBA/script/rman_ORCL.sh 2>&1
#00 05,17 * * * /home/oracle/DBA/script/rman_arch_ORCL.sh 2>&1

### Data Collection Tool (ashurei@sk.com)
00 01 * * 6 /home/oracle/DCT-oracle.sh
```

### node#2
```
### Manage log of Oracle (ashurei@sk.com)
20 01 * * * /home/oracle/DBA/script/ManageLog-oracle.sh

### Manage archive log (ashurei@sk.com) (only node#2)
30 01 * * * /home/oracle/DBA/script/ManageLog-archive.sh

### purge stats (ashurei@sk.com) (only node#2)
00 23 * * * /home/oracle/DBA/script/purge_stats.sh

### Datapump (ashurei@sk.com)
00 02 * * * /home/oracle/DBA/script/expdp_ORCL.sh

### RMAN (ashurei@sk.com)
#00 23 * * 0,2,4 /home/oracle/DBA/script/rman_ORCL.sh 2>&1
#00 05,17 * * * /home/oracle/DBA/script/rman_arch_ORCL.sh 2>&1

### Data Collection Tool (ashurei@sk.com)
05 01 * * 6 /home/oracle/DCT-oracle.sh
```

## Grid 계정
```
### Manage log of Grid
10 01 * * * /home/grid/DBA/script/ManageLog-grid.sh
```
