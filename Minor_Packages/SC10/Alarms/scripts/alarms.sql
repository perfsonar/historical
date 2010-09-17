CREATE TABLE ps_tl1_alarms (
  metadataId INTEGER NOT NULL,
  alarmId VARCHAR(255) NOT NULL,
  facility VARCHAR(10) NOT NULL,
  type VARCHAR(32) NOT NULL,
  severity VARCHAR(2) NOT NULL,
  serviceAffecting BOOLEAN NOT NULL,
  description VARCHAR(100) NOT NULL,

  measuredStartTime INTEGER NOT NULL,
  machineStartTime INTEGER NOT NULL,
  firstObservedTime INTEGER NOT NULL,
  lastObservedTime INTEGER NOT NULL,

  UNIQUE (metadataId, alarmId));

CREATE TABLE ps_tl1_metadata (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  name    VARCHAR(255) NOT NULL,
  address VARCHAR(255),
  UNIQUE (name));
