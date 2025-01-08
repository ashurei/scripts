SET HEADING OFF
SET FEEDBACK OFF
SET TIME OFF TIMING OFF
SET lines 5000 PAGES 0
SET ECHO ON
SET TERM OFF

COL value for 9999999999999999999999999999

select 'oracle_realtime,host='||y.host_name||',oracle_sid='||y.instance_name||' '||x.val
  from
  (
    select listagg(stat,',') within group (order by stat) as val
      from
      (
        select replace(replace(replace(name,' ','_'),'(',''),')','')||'='||to_char(value) as stat
          from
          (
            select name, value from v\$sysstat where name in ( 'user calls'
                                                            , 'user commits'
                                                            , 'user rollbacks'
                                                            , 'execute count'
                                                            , 'user commit'
                                                            , 'user rollbacks'
                                                            , 'recursive calls'
                                                            , 'session logical reads'
                                                            , 'db block gets'
                                                            , 'db block gets direct'
                                                            , 'db block changes'
                                                            , 'consistent gets'
                                                            , 'consistent gets direct'
                                                            , 'consistent changes'
                                                            , 'CPU used by this session'
                                                            , 'physical reads'
                                                            , 'physical reads direct'
                                                            , 'physical reads direct (lob)'
                                                            , 'physical read total IO requests'
                                                            , 'physical read total bytes'
                                                            , 'parse time cpu'
                                                            , 'parse time elapsed'
                                                            , 'parse count (total)'
                                                            , 'parse count (hard)'
                                                            , 'sorts (memory)'
                                                            , 'sorts (disk)'
                                                            , 'sorts (rows)'
                                                            , 'table scans (short tables)'
                                                            , 'table scans (long tables)'
                                                            , 'table scans (rowid ranges)'
                                                            , 'table scans (cache partitions)'
                                                            , 'table scans (direct read)'
                                                            , 'table scan rows gotten'
                                                            , 'table scan blocks gotten'
                                                            , 'physical writes'
                                                            , 'physical writes direct'
                                                            , 'physical write IO requests'
                                                            , 'physical write total bytes'
                                                            , 'physical writes non checkpoint'
                                                            , 'redo size'
                                                            , 'redo writes'
                                                            , 'redo entries'
                                                            , 'redo log space requests'
                                                            , 'leaf node splits'
                                                            , 'leaf node 90-10 splits'
                                                            , 'enqueue timeouts'
                                                            , 'enqueue waits'
                                                            , 'enqueue deadlocks'
                                                            , 'enqueue requests'
                                                            , 'enqueue conversions'
                                                            , 'enqueue releases'
                                                            , 'bytes sent via SQL*Net to client'
                                                            , 'bytes received via SQL*Net from client'
                                                            , 'bytes sent via SQL*Net to dblink'
                                                            , 'bytes received via SQL*Net from dblink'
                                                            )
            union all
            select 'seq',nvl(sum(seconds_in_wait),0) from v\$session_wait where event ='db file sequential read'
            union all
            select 'librarycache_pinhits' as name, sum(pinhits) as value from v\$librarycache
            union all
            select 'librarycache_pins' as name, sum(pins) as value from v\$librarycache
            union all
            select name, bytes as value from v\$sgainfo
            union all
            select lower(status)||'_session' as name, count(*) as value from v\$session group by status
            union all
            select b.name, sum(a.value) as value from v\$sesstat a, v\$statname b where a.statistic# = b.statistic# and b.name in ('session pga memory', 'opened cursors current', 'session uga memory') group by b.name
            union all
            select 'latch_misses_sum' as name, sum(a.misses) as value from v\$latch a
            union all
            select 'latch_gets_sum' as name, sum(a.gets) as value from v\$latch a
            union all
            select 'blocking_session' as name, count(*) as value from v\$session where blocking_session is not null
            union all
            select 'buffer_cache_hit_ratio' as name,
                   round(((1-(sum(decode(name,'physical reads' , value, 0))/
                             (sum(decode(name,'db block gets'  , value, 0))+
                             (sum(decode(name,'consistent gets', value, 0)) ))))*100),2) from v\$sysstat
          )
      )
  ) x, v\$instance y;
EOF
