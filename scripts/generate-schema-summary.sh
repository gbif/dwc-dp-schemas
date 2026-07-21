#!/usr/bin/env bash
# scripts/generate-schema-summary.sh
#
# Compiles src/main/resources/schemas/{version}/table-schemas/*.json into a single compact
# src/main/resources/schemas/{version}/schema-summary.json, alongside index.json and
# dwc-dp-profile.json, for every published bundle version.
#
# Usage:
#   scripts/generate-schema-summary.sh          # regenerate for every version found
#   scripts/generate-schema-summary.sh 1.0_DEV  # regenerate for just this one version
#
# Purpose: table-schemas/*.json carries full prose (description, comments, examples) for human
# reading; schema-summary.json strips that down to field name/type/constraints/relationships
# only, so a tool consuming many tables at once (an LLM, a codegen script) doesn't pay the token
# or parsing cost of prose it doesn't need. Committed to git rather than generated on the fly at
# load time, since it's a docs artifact, not something read by any consumer of this jar at
# runtime.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMAS_ROOT="${REPO_ROOT}/src/main/resources/schemas"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found on PATH" >&2
  exit 1
fi
if [[ ! -d "${SCHEMAS_ROOT}" ]]; then
  echo "No such directory: ${SCHEMAS_ROOT}" >&2
  exit 1
fi

# jq filter, applied per table-schemas/*.json file (each already has name/fields/primaryKey/
# weakPrimaryKey/foreignKeys/weakForeignKeys at its top level — same shape TableSchema.fromJson
# already expects, so this filter mirrors that model rather than inventing a new one).
#
# fk/weakFk are kept as SEPARATE arrays rather than a single array with a "weak" boolean flag —
# deliberately: the distinction is the one thing this file exists to make impossible to miss
# when skimming, and a flag sitting inside each object is easy to scan past. Two named arrays
# force the question "does this table have any weak relationships" to be answered by which
# array has entries, not by reading a per-field property.
#
# A targetless weakForeignKey (fields declared with no 'reference' object at all — real, valid,
# see ForeignKey.hasTarget() in datagen-core) serializes with "ref": null, so its absence of a
# target is visible in the summary rather than silently dropped by the filter.
JQ_FILTER='
  {
    name: .name,
    pk: .primaryKey,
    weakPk: .weakPrimaryKey,
    fields: [
      .fields[] | {
        name: .name,
        type: .type
      }
      + (if (.constraints.required // false) then {req: true} else {} end)
      + (if (.constraints.unique // false) then {uniq: true} else {} end)
      + (if .constraints.enum then {enum: .constraints.enum} else {} end)
      + (if .constraints.minimum then {min: .constraints.minimum} else {} end)
      + (if .constraints.maximum then {max: .constraints.maximum} else {} end)
    ],
    fk: [
      (.foreignKeys // [])[] | {
        field: .fields,
        ref: (
          if .reference and (.reference.fields != null) then
            (if (.reference.resource // "") == "" then .name else .reference.resource end)
            + "." + .reference.fields
          else null end
        )
      }
    ],
    weakFk: [
      (.weakForeignKeys // [])[] | {
        field: .fields,
        ref: (
          if .reference and (.reference.fields != null) then
            (if (.reference.resource // "") == "" then .name else .reference.resource end)
            + "." + .reference.fields
          else null end
        )
      }
    ]
  }
'

generate_for_version() {
  local version="$1"
  local version_dir="${SCHEMAS_ROOT}/${version}"
  local table_dir="${version_dir}/table-schemas"
  local out="${version_dir}/schema-summary.json"

  if [[ ! -d "${table_dir}" ]]; then
    echo "Skipping ${version}: no table-schemas/ directory at ${table_dir}" >&2
    return
  fi

  local tables_json
  tables_json=$(
    jq -n --arg version "${version}" --arg generated "$(date -u +%Y-%m-%d)" '
      {version: $version, generated: $generated, tables: {}}
    '
  )

  local file table_summary table_name
  for file in "${table_dir}"/*.json; do
    table_summary=$(jq -c "${JQ_FILTER}" "${file}")
    table_name=$(jq -r '.name' "${file}")
    tables_json=$(echo "${tables_json}" | jq --arg name "${table_name}" --argjson t "${table_summary}" \
      '.tables[$name] = ($t | del(.name))')
  done

  echo "${tables_json}" | jq -c '.' > "${out}"
  echo "Wrote ${out} ($(wc -c < "${out}") bytes, $(jq '.tables | length' "${out}") tables)"
}

if [[ $# -ge 1 ]]; then
  # A specific version was named — regenerate just that one.
  generate_for_version "$1"
else
  # No version named — discover every version directory and regenerate all of them. This is
  # the default because there's no reason "regenerate the summaries" should be a per-version
  # manual chore: every published bundle version should always have an up-to-date summary.
  found_any=false
  for version_dir in "${SCHEMAS_ROOT}"/*/; do
    version="$(basename "${version_dir}")"
    if [[ -d "${version_dir}/table-schemas" ]]; then
      found_any=true
      generate_for_version "${version}"
    fi
  done
  if [[ "${found_any}" == "false" ]]; then
    echo "No version directories with a table-schemas/ subdirectory found under ${SCHEMAS_ROOT}" >&2
    exit 1
  fi
fi