// voxon_cli: usa el motor local desde la terminal o desde otro programa.
//
//   voxon_cli --version
//   voxon_cli <base.db> info
//   voxon_cli <base.db> call <método> [params-json] [--actor <id>]
//   voxon_cli <base.db> stdio        una solicitud JSON por línea (entrada) → una respuesta por línea (salida)

#include <cstring>
#include <iostream>
#include <string>

#include <nlohmann/json.hpp>

#include "voxon/voxon.h"

#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#endif

namespace {

int usage() {
  std::cerr << "Uso:\n"
               "  voxon_cli --version\n"
               "  voxon_cli <base.db> info\n"
               "  voxon_cli <base.db> call <método> [params-json] [--actor <id>]\n"
               "  voxon_cli <base.db> stdio\n";
  return 2;
}

// Imprime la respuesta y devuelve 0 si fue exitosa.
int run(voxon_engine* engine, const std::string& request) {
  char* response = voxon_execute(engine, request.c_str());
  if (response == nullptr) {
    std::cerr << "Sin memoria\n";
    return 1;
  }
  const auto parsed = nlohmann::json::parse(response, nullptr, false);
  std::cout << (parsed.is_discarded() ? std::string(response) : parsed.dump(2)) << "\n";
  const bool ok = !parsed.is_discarded() && parsed.value("ok", false);
  voxon_free(response);
  return ok ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
#ifdef _WIN32
  SetConsoleOutputCP(CP_UTF8);
#endif
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::cout << voxon_version() << "\n";
    return 0;
  }
  if (argc < 3) {
    return usage();
  }

  char* error = nullptr;
  voxon_engine* engine = voxon_open(argv[1], &error);
  if (engine == nullptr) {
    std::cerr << (error != nullptr ? error : "No se pudo abrir la base de datos") << "\n";
    voxon_free(error);
    return 1;
  }

  const std::string command = argv[2];
  int status = 0;
  if (command == "info") {
    status = run(engine, R"({"method":"system.info"})");
  } else if (command == "call" && argc >= 4) {
    nlohmann::json request = {{"method", argv[3]}};
    for (int i = 4; i < argc; ++i) {
      if (std::strcmp(argv[i], "--actor") == 0 && i + 1 < argc) {
        request["actor"] = argv[++i];
      } else {
        auto params = nlohmann::json::parse(argv[i], nullptr, false);
        if (params.is_discarded() || !params.is_object()) {
          std::cerr << "Los parámetros deben ser un objeto JSON válido\n";
          voxon_close(engine);
          return 2;
        }
        request["params"] = std::move(params);
      }
    }
    status = run(engine, request.dump());
  } else if (command == "stdio") {
    std::string line;
    while (std::getline(std::cin, line)) {
      if (line.empty()) {
        continue;
      }
      char* response = voxon_execute(engine, line.c_str());
      std::cout << (response != nullptr ? response : R"({"ok":false,"error":{"code":"internal_error"}})") << "\n"
                << std::flush;
      voxon_free(response);
    }
  } else {
    status = usage();
  }

  voxon_close(engine);
  return status;
}
