package argy

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

// Prefix for long form of argument names
LONG_ARG_PREFIX :: "--"
// Prefix for short form of argument names
SHORT_ARG_PREFIX :: "-"
// What goes between argument name and argument value if they're not
// separated by a space
ARG_EQUALS :: "="

/*
 * Types
 */

// Descriptor for an argument your program can take.
Descriptor :: struct {
	name: string,
	match: []Match_Mode,
	allow_multiple: bool,
	location: Location,
	value_type: Maybe(Value_Type),
	value_required: bool,
}

// Format that an argument can be passed to your program's CLI.
Match_Mode :: union #no_nil {
	string,
	Long_Short,
}

// Signifies the user can pass the argument as a long/short Linux-style alias
// (--long, -s)
Long_Short :: struct {
	long: string,
	short: string,
}

// Location an argument can appear. The zero value signifies anywhere.
Location :: union {
	Simple_Location,
	After,
	Right_After,
}

// Simple location specifiers for arguments.
Simple_Location :: enum {
	Anywhere,
	Beginning,
	End,
}

After :: struct { what: string }
Right_After :: struct { what: string }

// Valid types for argument values (--arg=value)
Value_Type :: enum {
	String,
	Bool,
	Integer,
}

// A parsed argument.
Arg :: struct {
	name: string,
	matched: string,
	valid: bool,
	position: uint,
	value: Value,
}

Value :: union {
	string,
	bool,
	int,
}

// Parses arguments and returns an Arg for each descriptor. The arg slice will
// need to be destroyed on your end.
parse :: proc(descriptors: []Descriptor, arguments: []string) -> []Arg {
	result: [dynamic]Arg
	reserve(&result, len(descriptors))

	for _, d in descriptors {
		desc := &descriptors[d]
		for _, md in descriptors {
			m_desc := &descriptors[md]
			if m_desc != desc && m_desc.name == desc.name {
				panic("duplicate descriptor names")
			}
		}
	}

	c := 1 // skip argv[0], which is the call path
	for c < len(arguments) {
		c += parse_argument(&result, descriptors, arguments, c)
	}

	return result[:]
}

@(private)
parse_argument :: proc(into: ^[dynamic]Arg, descs: []Descriptor, args: []string, idx: int) -> int {
	chomped := 1
	next_arg := args[idx]

	for desc in descs {
		if !desc.allow_multiple {
			already_matched := false
			for matched_arg in into {
				if matched_arg.name == desc.name {
					already_matched = true
					break
				}
			}
			if already_matched { continue }
		}

		matched := false
		value: Value

		matches_name := false
		matches_location := false
		matches_value := false

		// Match against name--
		// * If there are at least one name formats provided, match against each
		// * Otherwise, match against the name of the argument descriptor
		if len(desc.match) > 0 {
			for match in desc.match {
				if name_matches(desc, match, next_arg) {
					matches_name = true
					break
				}
			}
		} else {
			matches_name = name_matches(desc, "", next_arg)
		}
	
		if !matches_name { continue }

		// Matched the name, now we check for validity and value
		switch in desc.location {
		
		case Simple_Location:
			switch desc.location.(Simple_Location) {
			case .Anywhere:
				matches_location = true
			case .Beginning:
				matches_location = len(into) == 0
			case .End:
				matches_location = idx == len(args) - 1
			}

		case After:
			for i := 0; i < len(into); i += 1 {
				if into[i].name == desc.location.(After).what {
					matches_location = true
					break
				}
			}

		case Right_After:
			if len(into) > 0 {
				matches_location = into[len(into) - 1].name == desc.location.(Right_After).what
			}

		}

		if !matches_location { continue }

		// Get a value for the argument if it takes one
		if desc.value_type != nil {
			// Arg is in match of --a=true
			if fused_index := strings.index(next_arg, ARG_EQUALS); fused_index != -1 {
				value = value_from_string(desc.value_type.(Value_Type), next_arg[fused_index + 1:])
			} else {
				if idx < len(args) - 1 {
					v := value_from_string(desc.value_type.(Value_Type), args[idx + 1])
					if v != nil {
						value = v
						chomped += 1
					}
				}
			}
			if desc.value_required && value != nil { matches_value = true }
		} else {
			matches_value = true
		}

		if !matches_value { continue }

		// This one matches fully! Add it to the list of matched args
		append(into, Arg{
			name = desc.name,
			matched = next_arg,
			valid = true,
			position = uint(idx),
			value = value,
		})
	}

	return chomped
}

@(private)
name_matches :: proc(desc: Descriptor, match: Match_Mode, arg: string) -> bool {
	matches_name := false
	
	switch in match {
	
	// Match aliased argument (-p, --plong)
	case Long_Short:
		alias := match.(Long_Short)
		if desc.value_type != nil {
			// match against --/- followed by long/short alias for this argument
			// we have to check prefix instead of == because you can specify values
			// for arguments, meaning an argument might be passed as --arg=24
			matches_name =
				strings.has_prefix(
					strings.trim_prefix(arg, LONG_ARG_PREFIX),
					alias.long,
				) ||
				strings.has_prefix(
					strings.trim_prefix(arg, SHORT_ARG_PREFIX),
					alias.short,
				)
		} else {
			matches_name =
				strings.trim_prefix(arg, LONG_ARG_PREFIX) == alias.long ||
				strings.trim_prefix(arg, SHORT_ARG_PREFIX) == alias.short
		}

	// Match direct string argument
	case string:
		if desc.value_type != nil {
			// If Any_Of is an empty string slice, match against the name
			// This means not specifying `match` will default to matching against the
			// argument name
			if match.(string) == "" {
				if arg == desc.name {
					matches_name = true
				} else {
					if strings.has_prefix(arg, desc.name) {
						matches_name =
							strings.has_prefix(strings.trim_prefix(arg, desc.name), ARG_EQUALS)
					}
				}
			} else {
				match := match.(string)
				if strings.has_prefix(arg, match) {
					if arg == match || strings.has_prefix(strings.trim_prefix(arg, match), ARG_EQUALS) {
						matches_name = true
						break
					}
				}
			}
		} else {
			if match.(string) == "" {
				matches_name = desc.name == arg
			} else {
				if match.(string) == arg {
					matches_name = true
					break
				}
			}
		}
	}
	
	return matches_name
}

@(private)
value_from_string :: proc(type: Value_Type, str: string) -> Value {
	switch type {
	
	case .String:
		return Value(str)

	case .Bool:
		if b, ok := strconv.parse_bool(str); ok {
			return Value(b)
		}


	case .Integer:
		if i, ok := strconv.parse_int(str); ok {
			return Value(i)
		}
	}

	return nil
}
