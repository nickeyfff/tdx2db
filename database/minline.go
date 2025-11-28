package database

import (
	"database/sql"
	"fmt"

	_ "github.com/duckdb/duckdb-go/v2"
)

var minLineColumns = []string{
	"symbol VARCHAR",
	"open DOUBLE",
	"high DOUBLE",
	"low DOUBLE",
	"close DOUBLE",
	"amount DOUBLE",
	"volume BIGINT",
	"datetime TIMESTAMP",
}

var OneMinLineSchema = TableSchema{
	Name:    "raw_stocks_1min",
	Columns: minLineColumns,
}

var FiveMinLineSchema = TableSchema{
	Name:    "raw_stocks_5min",
	Columns: minLineColumns,
}

func Import1MinLineCsv(db *sql.DB, csvPath string) error {
	if err := CreateTable(db, OneMinLineSchema); err != nil {
		return fmt.Errorf("failed to create table: %w", err)
	}

	if err := ImportCSV(db, OneMinLineSchema, csvPath); err != nil {
		return fmt.Errorf("failed to import CSV: %w", err)
	}

	return nil
}

func Import5MinLineCsv(db *sql.DB, csvPath string) error {
	if err := CreateTable(db, FiveMinLineSchema); err != nil {
		return fmt.Errorf("failed to create table: %w", err)
	}

	if err := ImportCSV(db, FiveMinLineSchema, csvPath); err != nil {
		return fmt.Errorf("failed to import CSV: %w", err)
	}

	return nil
}

// Create5MinStockViews 创建用于 5 分钟股票数据管理的三个视图：
// - v_cold_stocks_5min: 从 Parquet 文件加载历史 5 分钟冷数据。
// - raw_stocks_5min_temp: 用于存储当天 5 分钟数据的临时表，每日更新后清空。
// - v_stocks_5min: 合并冷数据、临时热数据和最终清洗后的原始数据，并根据优先级去重。
// 函数接受数据库连接和 Parquet 文件的 glob 路径作为输入。
func Create5MinStockViews(db *sql.DB, parquetPath string) error {
	// 1. v_cold_stocks_5min
	query1 := fmt.Sprintf(`
	CREATE OR REPLACE VIEW v_cold_stocks_5min AS
	SELECT * FROM read_parquet(
		'%s',
		hive_partitioning = true,
		union_by_name = true
	);
	`, parquetPath)

	if _, err := db.Exec(query1); err != nil {
		return fmt.Errorf("failed to create v_cold_stocks_5min: %w", err)
	}

	// 2. raw_stocks_5min_temp
	// Ensure the base table exists
	if err := CreateTable(db, FiveMinLineSchema); err != nil {
		return fmt.Errorf("failed to create table raw_stocks_5min: %w", err)
	}

	query2 := `
	CREATE TABLE IF NOT EXISTS raw_stocks_5min_temp AS
	SELECT *
	FROM raw_stocks_5min
	WHERE false;
	`
	if _, err := db.Exec(query2); err != nil {
		return fmt.Errorf("failed to create raw_stocks_5min_temp: %w", err)
	}

	// 3. v_stocks_5min
	query3 := `
	CREATE OR REPLACE VIEW v_stocks_5min AS
	SELECT 
		* EXCLUDE (_priority) 
	FROM (
		-- 1. 历史冷数据 (Parquet归档)
		-- 优先级：最低 (1)
		SELECT *, 1 as _priority 
		FROM v_cold_stocks_5min

		UNION ALL BY NAME

		-- 2. 盘中实时热数据 (Temp表)
		-- 优先级：中等 (2)。如果还没收盘，或者还没运行清洗脚本，就看它。
		SELECT *, 2 as _priority 
		FROM raw_stocks_5min_temp

		UNION ALL BY NAME

		-- 3. 盘后最终清洗数据 (Raw表)
		-- 优先级：最高 (3)。这是TDX导出的铁律，只要它有数据，就覆盖上面两个。
		SELECT *, 3 as _priority 
		FROM raw_stocks_5min
	)
	-- 核心逻辑：按 [股票代码 + 时间] 分组，取优先级最高的那一条
	QUALIFY ROW_NUMBER() OVER (
		PARTITION BY symbol, datetime 
		ORDER BY _priority DESC
	) = 1;
	`
	if _, err := db.Exec(query3); err != nil {
		return fmt.Errorf("failed to create v_stocks_5min: %w", err)
	}

	return nil
}
