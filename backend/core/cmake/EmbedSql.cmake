# Genera un .cpp con las migraciones SQL incrustadas como bytes, para que el
# motor funcione sin archivos externos en cualquier equipo.
#
# Uso (modo script):
#   cmake -DOUTPUT=<archivo.cpp> -DINPUTS="a.sql|b.sql" -P EmbedSql.cmake

string(REPLACE "|" ";" INPUTS "${INPUTS}")
list(SORT INPUTS)

set(arrays "")
set(entries "")
set(index 0)
foreach(input IN LISTS INPUTS)
  get_filename_component(name "${input}" NAME)
  file(READ "${input}" hex HEX)
  string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
  string(APPEND arrays "const unsigned char kMigration${index}[] = {${bytes}0x00};\n")
  string(APPEND entries
    "      {\"${name}\", std::string_view(reinterpret_cast<const char*>(kMigration${index}), sizeof(kMigration${index}) - 1)},\n")
  math(EXPR index "${index} + 1")
endforeach()

file(WRITE "${OUTPUT}" "// Generado por EmbedSql.cmake a partir de backend/sql/migrations. No editar.
#include \"db/migrations.hpp\"

namespace voxon::db {
namespace {
${arrays}}  // namespace

const std::vector<Migration>& embeddedMigrations() {
  static const std::vector<Migration> migrations = {
${entries}  };
  return migrations;
}

}  // namespace voxon::db
")
