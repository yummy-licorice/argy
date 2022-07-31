package argy_example

import "core:fmt"
import "core:os"
import argy ".."

main :: proc() {
	args := argy.parse({
		{name = "report", location = .Beginning},
		{name = "hum", location = .Beginning},
		{name = "check", location = .Beginning},

		// Arguments valid for `report` subcommand
		{
			name = "report_what",
			match = {argy.Long_Short{long = "contents", short = "c"}},
			location = argy.Right_After{"report"},
			value_type = .String,
			value_required = true,
		},

		// Arguments valid for `hum` subcommand
		{
			name = "hum_what",
			match = {"song", "drum", "or_else"},
			location = argy.After{"hum"},
		},
		{
			name = "hum_how",
			match = {argy.Long_Short{long = "technique", short = "t"}},
			location = argy.After{"hum"},
			value_type = .String,
			value_required = true,
		},
		{
			name = "loudly",
			match = {argy.Long_Short{long = "loud", short = "l"}},
		},

		// Arguments valid for `check` subcommand0
		{
			name = "check_scope",
			match = {"all", "some", "whatever"},
			location = argy.After{"check"},
		},
	}, os.args); defer delete(args)

	fmt.println(args)
}
