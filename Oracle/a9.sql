COL "SID"               FORMAT A6
COL "OSPID"             FORMAT A6
COL "Logon Info"        FORMAT A11
COL "Module Info"       FORMAT A31
COL "Run Time"          FORMAT A8
COL SQL                 heading "SQL|L/P/BC/CC"FORMAT A40
COL EVENT               FORMAT A35

SET PAGESIZE 10000
SET LINESIZE 300
SET FEED ON
SET HEAD ON
SET TERMOUT ON

select /*+ leading(s) no_expand use_nl(sql sl) use_nl(sql) */
      s.sid || chr(10) || '>' || s.serial# "SID", p.spid "OSPID",
      substr(sw.event,1,24) || chr(10) ||
                decode(command,
                0,'BACKGROUND',
                1,'CREATE TABLE',
                2,'INSERT',
                3,'SELECT',
                4,'CREATE CLUSTER',
                5,'ALTER CLUSTER',
                6,'UPDATE',
                7,'DELETE',
                8,'DROP',
                9,'CREATE INDEX',
                10,'DROP INDEX',
                11,'ALTER INDEX',
                12,'DROP TABLE',
                13,'---',
                14,'---',
                15,'ALTER TABLE',
                16,'---',
                17,'GRANT',
                18,'REVOKE',
                19,'CREATE SYNONYM',
                20,'DROP SYNONYM',
                21,'CREATE VIEW',
                22,'DROP VIEW',
                23,'---',
                24,'---',
                25,'---',
                26,'LOCK TABLE',
                27,'NO OPERATION',
                28,'RENAME',
                29,'COMMENT',
                30,'AUDIT',
                31,'NOAUDIT',
                32,'CREATE EXTERNAL DATABASE',
                33,'DROP EXTERNAL DATABASE',
                34,'CREATE DATABASE',
                35,'ALTER DATABASE',
                36,'CREATE ROLLBACK SEGMENT',
                37,'ALTER ROLLBACK SEGMENT',
                38,'DROP ROLLBACK SEGMENT',
                39,'CREATE TABLESPACE',
                40,'ALTER TABLESPACE',
                41,'DROP TABLESPACE',
                42,'ALTER SESSION',
                43,'ALTER USER',
                44,'COMMIT',
                45,'ROLLBACK',
                46,'SAVEPOINT',
                47,'PL/SQL EXECUTE',
                48,'SET TRANSACTION',
                49,'ALTER SYSTEM SWITCH LOG',
                50,'EXPLAIN',
                51,'CREATE USER',
                52,'CREATE ROLE',
                53,'DROP USER',
                54,'DROP ROLE',
                55,'SET ROLE',
                56,'CREATE SCHEMA',
                57,'CREATE CONTROL FILE',
                58,'ALTER TRACING',
                59,'CREATE TRIGGER',
                60,'ALTER TRIGGER',
                61,'DROP TRIGGER',
                62,'ANALYZE TABLE',
                63,'ANALYZE INDEX',
                64,'ANALYZE CLUSTER',
                65,'CREATE PROFILE',
                66,'DROP PROFILE',
                67,'ALTER PROFILE',
                68,'DROP PROCEDURE',
                70,'ALTER RESOURCE COST',
                71,'CREATE SNAPSHOT LOG',
                72,'ALTER SNAPSHOT LOG',
                73,'DROP SNAPSHOT LOG',
                74,'CREATE SNAPSHOT',
                75,'ALTER SNAPSHOT',
                76,'DROP SNAPSHOT',
                84,'-',
                85,'TRUNCATE TABLE',
                86,'TRUNCATE CLUSTER',
                87,'-',
                88,'ALTER VIEW',
                89,'-',
                90,'-',
                91,'CREATE FUNCTION',
                92,'ALTER FUNCTION',
                93,'DROP FUNCTION',
                94,'CREATE PACKAGE',
                95,'ALTER PACKAGE',
                96,'DROP PACKAGE',
                97,'CREATE PACKAGE BODY',
                98,'ALTER PACKAGE BODY',
                99,'DROP PACKAGE BODY',
                -67,'MERGE',
--              command||' - ???') || ',' || s.username || ',[' || s.sql_hash_value || ']' event,
                command||' - ???') || ',' || s.username || ',[' || s.sql_id || ']' event,
      substr(decode(s.module,NULL,s.machine || ':' || substr(s.program,1,instr(s.program,'@')),s.module)||'('||s.action||')',1,30) || ',' || s.machine || chr(10) || to_char(s.logon_time,'YYYY.MM.DD HH24:MI:SS') "Module Info",
      to_char(s.LAST_CALL_ET,'FM999,999') || chr(10) || nvl(to_char(sl.TIME_REMAINING,'FM999,999'),' ') "Run Time",
      substr(sql.sql_text,1,37) || chr(10) || ' >' || (si.BLOCK_GETS+si.CONSISTENT_GETS) || '/' || si.PHYSICAL_READS || '/' || si.BLOCK_CHANGES || '/' || CONSISTENT_CHANGES SQL ,
      s.username || chr(10) || s.status "Logon Info"
from
        v$session s,
        v$session_wait sw,
        v$sql sql,
        v$session_longops sl,
        v$sess_io si,
        v$process p
where
--    (
--    s.status <> 'INACTIVE' and s.status<>'SNIPED' --and s.status<>'KILLED'
--    )
    s.paddr=p.addr
    and s.status in ('ACTIVE','KILLED')
    and s.sid = sw.sid
    and s.sql_address = sql.address(+)
    and s.sql_hash_value = sql.hash_value(+)
--    and s.sql_id = sql.sql_id(+)
    and sql.CHILD_NUMBER(+) = 0
    and s.username <> 'SYS'
--    and s.username='TMS21'
    and s.audsid <> userenv('SESSIONID')
    and sw.event not in ('pipe get','queue messages')
    and s.sid = sl.sid(+)
    and sl.sofar(+) < sl.totalwork(+)
    and sl.units(+) = 'Blocks'
    and sl.time_remaining(+)>0
    and sw.sid = si.sid(+)
    and sw.event not like 'Streams%'
order by s.LAST_CALL_ET desc, s.sid
/
