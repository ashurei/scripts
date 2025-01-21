#!/bin/bash
########################################################
# Description : Monitor Oracle tablespace usage with telegraf
# Create DATE : 2025.01.21
# Last Update DATE : 2025.01.21 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2025
########################################################

export ORACLE_BASE=/oracle/database
export ORACLE_HOME=${ORACLE_BASE}/product/19
export ORACLE_SID=ORCL1
SQL="/oracle/backup/telegraf_oracle.sql"

${ORACLE_HOME}/bin/sqlplus -S mon/mon << EOF
SET HEADING OFF
SET FEEDBACK OFF
SET TIME OFF TIMING OFF
SET lines 5000 PAGES 0
SET ECHO ON
SET TERM OFF

SELECT 'tablespace_usage,tablespace=' || t.tn || ' usage_percent=' ||
       to_char( round((t.sizes - f.sizes) /t.sizes * 100,2), 'FM9990.99' ) pct
  FROM  ( SELECT tablespace_name tn,
                 sum(bytes)/1024/1024 Sizes
            FROM   dba_data_files
           GROUP BY tablespace_name) t,
        ( SELECT tablespace_name tn,
                 sum(bytes)/1024/1024 sizes
            FROM dba_free_space
           GROUP BY tablespace_name) f
 WHERE t.tn = f.tn
 ORDER BY Pct desc
/
EOF
