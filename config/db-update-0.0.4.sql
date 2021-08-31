USE uravo;

ALTER TABLE server ADD uravo_version VARCHAR(15) AFTER perl_arch;
DELETE FROM rootcause_symptom WHERE rootcause_id=2;
DELETE FROM rootcause WHERE id=2;
