drop procedure if exists proc_partition_control;
delimiter $$
create procedure proc_partition_control (in v_dbname varchar(20), in v_tablename varchar(100), in v_drop_period INT, in v_add_period INT)
begin
  declare v_partition varchar(20);
  declare v_target varchar(20);
  declare done BOOLEAN DEFAULT FALSE;

  -- Get partition name before the period days.
  declare cur cursor for
    select partition_name
      from information_schema.PARTITIONS
     where table_schema = v_dbname
       and table_name = v_tablename
       and date_format(curdate() - INTERVAL v_drop_period DAY, '%Y%m%d') > substr(partition_name, 3);

  declare continue handler for not found set done = TRUE;

  -- drop partition
  open cur;
  read_loop: loop
    fetch cur into v_partition;
        IF done THEN
      LEAVE read_loop;
    END IF;

        SET @sql = CONCAT('ALTER TABLE ', v_dbname, '.', v_tablename, ' DROP PARTITION ', v_partition, ';');
        prepare stmt from @sql;
        execute stmt;
        deallocate prepare stmt;
  end loop;

  close cur;

  -- add partition
  select CONCAT("'", date_format(curdate() + INTERVAL (v_add_period + 1) DAY, '%Y-%m-%d'), "'") into v_target;
  select CONCAT("p_", date_format(curdate() + INTERVAL v_add_period DAY, '%Y%m%d')) into v_partition;
  SET @sql = CONCAT('ALTER TABLE ', v_dbname, '.', v_tablename, ' REORGANIZE PARTITION p_max INTO
                      (PARTITION ', v_partition, ' VALUES LESS THAN (', v_target, '), PARTITION p_max VALUES LESS THAN MAXVALUE);');
  prepare stmt from @sql;
  execute stmt;
  deallocate prepare stmt;

end $$
delimiter ;
