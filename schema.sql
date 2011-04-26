CREATE TABLE f1_2011 (
    -- required
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    round INTEGER NOT NULL,
    name TEXT NOT NULL,
    team TEXT NOT NULL,
    position TEXT NOT NULL,
    -- deleted during parsing, replaced with curr_value, prev_value
    -- value INTEGER NOT NULL,
    growth INTEGER NOT NULL,
    total_growth INTEGER NOT NULL,
    points INTEGER,
    victories INTEGER,
    podiums INTEGER,
    poles INTEGER,
    -- deleted during parsing, replaced with laps_completed, laps_attempted
    -- laps TEXT NOT NULL,
    overtakes INTEGER,
    popularity INTEGER NOT NULL,
    trend INTEGER NOT NULL,
    value_idx INTEGER NOT NULL,
    -- optional
    laps_completed INTEGER,
    laps_attempted INTEGER,
    name_short TEXT,
    name_abbr TEXT,
    curr_value INTEGER NOT NULL,
    prev_value INTEGER NOT NULL
);

