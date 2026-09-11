@abstract
class_name ValidationRule
extends RefCounted
## One structural concern of trial.json, checkable on its own.
##
## TrialValidator holds the rules and runs them all; a rule never decides
## whether a later one runs, so this is a composite and not a chain of
## responsibility. Each rule writes its findings to the report at the severity
## it chooses, which is the whole point: "is this fatal" belongs to the check,
## not to whichever function happens to consume its output.
##
## Rules are deliberately not registered as global classes. TrialValidator is
## the only thing that builds them, and the tests preload them by path.


## Read `data` and record what is wrong with it. Never raises; a rule that
## cannot understand its own section records that and returns.
@abstract func check(data: Dictionary, report: ValidationReport) -> void
