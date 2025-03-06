// ashurei@sk.com
// 2025.03.05.r6

package oracle

import (
	"database/sql"
	"fmt"
	"github.com/influxdata/telegraf"
	"github.com/influxdata/telegraf/plugins/inputs"
	_ "github.com/mattn/go-oci8"
	"strings"
	"sync"
)

type Oracle struct {
	Servers                     []string `toml:"servers"`
	GatherUserSessionCount      bool     `toml:"gather_user_session_count"`
	GatherActiveSessionCount    bool     `toml:"gather_active_session_count"`
	GatherOvertimeQuerySec      bool     `toml:"gather_over_time_query_sec"`
	GatherLatchTotalCount       bool     `toml:"gather_latch_total_count"`
	GatherWaitSessionCount      bool     `toml:"gather_wait_session_count"`
	GatherTransactionTotalCount bool     `toml:"gather_transaction_total_count"`
	GatherLogicalIoTotalCount   bool     `toml:"gather_logical_io_total_count"`
	GatherPysicalIoTotalCount   bool     `toml:"gather_physical_io_total_count"`
	GatherAsmDiskUsePerc        bool     `toml:"gather_asm_disk_use_perc"`
	GatherTablespacePerc        bool     `toml:"gather_tablespace_perc"`
	GatherLockQueryMsec         bool     `toml:"gather_lock_info"`
	GatherLockQueryCount        bool     `toml:"gather_lock_count"`
}

var sampleConfig = `
  servers = ["system/HelloOra@10.211.55.11:1521/ORCL"]

  #   gather_user_session_count      = true
  #   gather_active_session_count    = true
  #   gather_over_time_query_sec     = true
  #   gather_lock_info               = true
  #   gather_latch_total_count       = true
  #   gather_wait_session_count      = true
  #   gather_transaction_total_count = true
  #   gather_logical_io_total_count  = true
  #   gather_physical_io_total_count = true
  #   gather_asm_disk_use_perc       = true
  #   gather_tablespace_perc         = true
  #   gather_lock_count              = true
`

func (o *Oracle) SampleConfig() string {
	return sampleConfig
}

func (o *Oracle) Description() string {
	return "Read metrics from one or many oracle servers"
}

func (o *Oracle) Gather(acc telegraf.Accumulator) error {
	if len(o.Servers) == 0 {
		// default to localhost if nothing specified.
		err := o.gatherServer("localhost", acc)
		if err != nil {
			acc.AddError(err)
		}
		return nil
	}

	var wg sync.WaitGroup

	// Loop through each server and collect metrics
	for _, server := range o.Servers {
		wg.Add(1)
		go func(s string) {
			defer wg.Done()
			fmt.Println("server=%s", s)
			err := o.gatherServer(s, acc)
			if err != nil {
				acc.AddError(err)
			}
		}(server)
	}

	wg.Wait()

	//o.gatherServer(o.Servers[0], acc)

	return nil
}

func (o *Oracle) gatherServer(serv string, acc telegraf.Accumulator) error {

	db, err := sql.Open("oci8", serv)
	if err != nil {
		return err
	}
	defer db.Close()

	// 1) gatherSysstat
	if o.GatherWaitSessionCount {
		err = o.gatherSysstat(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherSysstat: %s", err))
		}
	}

	// 2) gatherSessionUsage
	if o.GatherUserSessionCount {
		err = o.gatherSessionUsage(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherSessionUsage: %s", err))
		}
	}

	// 3) gatherActiveSessionCount
	if o.GatherActiveSessionCount {
		err = o.gatherActiveSessionCount(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherActiveSessionCount: %s", err))
		}
	}

	// 4) gatherBlockingSession
	if o.GatherLockQueryCount {
		err = o.gatherBlockingSession(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherBlockingSession: %s", err))
		}
	}

	if o.GatherOvertimeQuerySec {
		err = o.gatherOvertimeQuerySec(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("OvertimeQuerySec: %s", err))
		}
	}

	if o.GatherLockQueryMsec {
		err = o.gatherLockQueryMsec(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("LockQueryMsec: %s", err))
		}
	}

	if o.GatherLatchTotalCount {
		err = o.gatherLatchTotalCount(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("LatchTotalCount: %s", err))
		}
	}

	if o.GatherLogicalIoTotalCount {
		err = o.gatherLogicalIoTotalCount(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("LogicalIoTotalCount: %s", err))
		}
	}

	if o.GatherPysicalIoTotalCount {
		err = o.gatherPysicalIoTotalCount(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("PysicalIoTotalCount: %s", err))
		}
	}

	// 10) gatherBufferCacheHitRatio
	if o.GatherTransactionTotalCount {
		err = o.gatherBufferCacheHitRatio(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherBufferCacheHitRatio: %s", err))
		}
	}

	// 11) gatherAsmDiskgroupPerc
	if o.GatherAsmDiskUsePerc {
		err = o.gatherAsmDiskgroupPerc(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherAsmDiskgroupPerc: %s", err))
		}
	}

	// 12) gatherTableSpacePerc
	if o.GatherTablespacePerc {
		err = o.gatherTableSpacePerc(db, serv, acc)
		if err != nil {
			acc.AddError(fmt.Errorf("gatherTableSpacePerc: %s", err))
		}
	}

	return nil
}

// 1) Gather sysstat
func (o *Oracle) gatherSysstat(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	query := `select name, value from v$sysstat
               where name in ( 'user calls'
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
            ) order by 1`

	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			name string
			value float64
		)
		if err := rows.Scan(&name, &value); err != nil {
			return err
		}
		tags["name"] = name
		fields["oracle_wait_session_count"] = uint64(value)
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 2) Gather Session usage (%)
func (o *Oracle) gatherSessionUsage(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	rows, err := db.Query("select round((select count(*) from v$session) / (select value from v$parameter where name='sessions') * 100, 2) as ratio from dual")
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (session_ratio float64)
		if err := rows.Scan(&session_ratio); err != nil {
			return err
		}
		fields["oracle_user_session_count"] = session_ratio
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 3) Gather active_session_count
func (o *Oracle) gatherActiveSessionCount(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	rows, err := db.Query("select count(*) as cnt from v$session where status = 'ACTIVE'")
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (cnt uint64)
		if err := rows.Scan(&cnt); err != nil {
			return err
		}
		fields["oracle_active_session_count"] = cnt
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 4) Gather Blocking session count
func (o *Oracle) gatherBlockingSession(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	rows, err := db.Query("select count(*) as value from v$session where blocking_session is not null")
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (cnt uint64)
		if err := rows.Scan(&cnt); err != nil {
			return err
		}
		fields["oracle_lock_query_count"] = cnt
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// Gather long query
func (o *Oracle) gatherOvertimeQuerySec(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	timeLimit := 5
	query := fmt.Sprintf(`select a.sql_id
	                            ,a.times_s
	                        from (
	                              select a.sql_id
	                                    ,b.sid
	                                    ,round(decode(a.ELAPSED_TIME, 0, 1, a.ELAPSED_TIME) / decode(a.EXECUTIONS, 0, 1, a.EXECUTIONS) / 1000000) AS times_s
	                                from v$sql a, v$session b
	                               where a.sql_id = b.sql_id
	                                 and a.hash_value = b.sql_hash_value
	                                 and b.status = 'ACTIVE'
	                                 and round(decode(a.ELAPSED_TIME, 0, 1, a.ELAPSED_TIME) / decode(a.EXECUTIONS, 0, 1, a.EXECUTIONS) / 1000000) > %d
	                               order by times_s desc
	                             ) a
	                       where rownum <= 10`, timeLimit)

	rows, err := db.Query(query)

	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			sqlID string
			timeS int64
		)

		if err := rows.Scan(&sqlID, &timeS); err != nil {
			return err
		}

		tags["sql_id"] = sqlID
		fields["oracle_overtime_query_sec"] = timeS
	}

	acc.AddFields("oracle", fields, tags)

	return nil
}

// Gather lock query (ms)
func (o *Oracle) gatherLockQueryMsec(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	timeLimit := 30
	query := fmt.Sprintf(`select c.sql_id
	                            ,a.ctime
	                        from v$lock a, v$session b, v$sqlarea c
	                       where a.request > 0
	                         and a.sid = b.sid
	                         and b.sql_id = c.sql_id
	                         and b.event like 'enq%'
	                         and a.ctime > %d`, timeLimit)

	rows, err := db.Query(query)

	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			sqlID string
			timeS int64
		)

		if err := rows.Scan(&sqlID, &timeS); err != nil {
			return err
		}

		tags["sql_id"] = sqlID
		fields["oracle_lock_query_msec"] = timeS
	}

	acc.AddFields("oracle", fields, tags)

	return nil
}

// Gather latch total count
func (o *Oracle) gatherLatchTotalCount(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	query := "select count(*) as cnt from v$session_wait where event like 'latch%'"

	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			cnt int64
		)

		if err := rows.Scan(&cnt); err != nil {
			return err
		}

		fields["oracle_latch_total_count"] = cnt
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// Gather logical_io_total_count
func (o *Oracle) gatherLogicalIoTotalCount(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	query := "select value from v$sysstat where name = 'session logical reads'"

	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			value float64
		)

		if err := rows.Scan(&value); err != nil {
			return err
		}

		fields["oracle_logical_io_total_count"] = value
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// Gather physical_io_total_count
func (o *Oracle) gatherPysicalIoTotalCount(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	query := "select value from v$sysstat where name = 'physical reads'"

	rows, err := db.Query(query)
	if err != nil {
		//fmt.Println("Error fetching addition")
		//fmt.Println(err)
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			value float64
		)

		if err := rows.Scan(&value); err != nil {
			return err
		}

		fields["oracle_physical_io_total_count"] = value
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 10) Gather Buffer_Cache_Hit_Ratio
func (o *Oracle) gatherBufferCacheHitRatio(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	// Buffer_Cache_Hit_Ratio
	query := `select round(1-((c.value-d.value)/((a.value+b.value)-(d.value))),4)*100 pct
	            from v$sysstat a, v$sysstat b, v$sysstat c, v$sysstat d
	           where a.name = 'consistent gets'
	             and b.name = 'db block gets'
	             and c.name = 'physical reads'
	             and d.name = 'physical reads direct'`

	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var pct float64
		if err := rows.Scan(&pct); err != nil {
			return err
		}

		fields["oracle_transaction_total_count"] = pct
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 11) Gather asm_diskgroup_perc
func (o *Oracle) gatherAsmDiskgroupPerc(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	rows, err := db.Query("select name, 100-round(free_mb / total_mb * 100, 2) pct from v$asm_diskgroup order by 2 desc")
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			name string
			pct float64
		)

		if err := rows.Scan(&name, &pct); err != nil {
			return err
		}

		tags["name"] = name
		fields["oracle_asm_disk_use_perc"] = pct
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

// 12) Gather tablespace usage
func (o *Oracle) gatherTableSpacePerc(db *sql.DB, serv string, acc telegraf.Accumulator) error {
	query := `SELECT t.tn "name"
	                ,round((t.sizes - f.sizes) /t.sizes * 100,2) "pct"
	            FROM ( SELECT tablespace_name tn
	                         ,sum(bytes)/1024/1024 Sizes
	                     FROM dba_data_files
	                    GROUP BY tablespace_name) t,
	                 ( SELECT tablespace_name tn
	                         ,sum(bytes)/1024/1024 sizes
	                     FROM dba_free_space
	                    GROUP BY tablespace_name) f
	           WHERE t.tn = f.tn
	           ORDER BY "pct" desc`

	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()

	servtag := getDSNTag(serv)
	tags := map[string]string{"server": servtag}
	fields := map[string]interface{}{}
	for rows.Next() {
		var (
			name string
			pct  float64
		)

		if err := rows.Scan(&name, &pct); err != nil {
			return err
		}

		tags["name"] = name
		fields["oracle_tablespace_perc"] = pct
	}
	acc.AddFields("oracle", fields, tags)

	return nil
}

func init() {
	inputs.Add("oracle", func() telegraf.Input {
		return &Oracle{
			GatherWaitSessionCount:      true,
			GatherUserSessionCount:      true,
			GatherActiveSessionCount:    true,
			GatherLockQueryCount:        true,
			//GatherOvertimeQuerySec:      true,
			//GatherLatchTotalCount:       true,
			//GatherLogicalIoTotalCount:   true,
			//GatherPysicalIoTotalCount:   true,
			//GatherLockQueryMsec:         true,
			GatherTransactionTotalCount: true,
			GatherAsmDiskUsePerc:        true,
			GatherTablespacePerc:        true,
		}
	})
}

func getDSNTag(dsn string) string {
	var c byte
	c = '@'
	st := strings.IndexByte(dsn, c)
	if st == -1 {
		st = 0
	}
	//fmt.Println(st) // 11: d가 12번째에 있으므로 11
	c = '/'
	sp := strings.LastIndexByte(dsn, c)
	if sp == -1 {
		sp = len(dsn)
	}
	//fmt.Println(sp) // -1: f는 없으므로 -1
	//fmt.Println(len(dsn)) // -1: f는 없으므로 -1

	safeSubstring := string(dsn[st+1 : sp])

	return safeSubstring
}
