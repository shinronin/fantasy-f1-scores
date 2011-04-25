CREATE TABLE f1_2011 (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    round INTEGER NOT NULL,
    name TEXT NOT NULL,
    name_short TEXT,
    name_abbr TEXT,
    team TEXT NOT NULL,
    position TEXT NOT NULL,
	-- replace with curr_value
    value INTEGER NOT NULL,
	-- add prev_value
    growth INTEGER NOT NULL,
    total_growth INTEGER NOT NULL,
    points INTEGER,
    victories INTEGER,
    podiums INTEGER,
    poles INTEGER,
    laps_completed INTEGER,
    laps_attempted INTEGER,
    overtakes INTEGER,
    popularity INTEGER NOT NULL,
    trend INTEGER NOT NULL,
    value_idx INTEGER NOT NULL
);

