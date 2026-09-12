#include "voxon/voxon.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "core/engine.hpp"
#include "core/error.hpp"
#include "core/json.hpp"

struct voxon_engine {
  std::unique_ptr<voxon::Engine> engine;
};

namespace {

char* copyString(const std::string& text) {
  auto* buffer = static_cast<char*>(std::malloc(text.size() + 1));
  if (buffer != nullptr) {
    std::memcpy(buffer, text.c_str(), text.size() + 1);
  }
  return buffer;
}

void setError(char** errorJson, std::string_view code, std::string_view message) {
  if (errorJson != nullptr) {
    *errorJson = copyString(voxon::dumpJson(voxon::errorResponse(code, message)));
  }
}

std::int64_t readOption(const voxon::Json& options, const char* key, std::int64_t fallback, std::int64_t min,
                        std::int64_t max) {
  const auto it = options.find(key);
  if (it == options.end() || it->is_null()) {
    return fallback;
  }
  if (!it->is_number_integer() || it->get<std::int64_t>() < min || it->get<std::int64_t>() > max) {
    throw voxon::ApiError(voxon::errc::kValidation, std::string("Opción inválida: ") + key);
  }
  return it->get<std::int64_t>();
}

}  // namespace

const char* voxon_version(void) { return VOXON_VERSION; }

voxon_engine* voxon_open(const char* path, char** error_json) {
  return voxon_open_with_options(path, nullptr, error_json);
}

voxon_engine* voxon_open_with_options(const char* path, const char* options_json, char** error_json) {
  if (error_json != nullptr) {
    *error_json = nullptr;
  }
  try {
    if (path == nullptr) {
      throw voxon::ApiError(voxon::errc::kInvalidRequest, "Falta la ruta de la base de datos");
    }
    voxon::EngineOptions options;
    if (options_json != nullptr && *options_json != '\0') {
      const auto json = voxon::Json::parse(options_json);
      if (!json.is_object()) {
        throw voxon::ApiError(voxon::errc::kInvalidRequest, "Las opciones deben ser un objeto JSON");
      }
      options.pinIterations =
          static_cast<std::uint32_t>(readOption(json, "pinIterations", options.pinIterations, 1, 10000000));
      options.loginMaxFailures =
          static_cast<int>(readOption(json, "loginMaxFailures", options.loginMaxFailures, 1, 1000));
      options.loginLockDuration =
          std::chrono::seconds(readOption(json, "loginLockSeconds", options.loginLockDuration.count(), 0, 86400));
    }
    auto handle = std::make_unique<voxon_engine>();
    handle->engine = voxon::Engine::open(path, options);
    return handle.release();
  } catch (const voxon::ApiError& error) {
    setError(error_json, error.code(), error.what());
  } catch (const voxon::Json::exception& error) {
    setError(error_json, voxon::errc::kInvalidRequest, error.what());
  } catch (const std::exception& error) {
    setError(error_json, voxon::errc::kInternal, error.what());
  }
  return nullptr;
}

char* voxon_execute(voxon_engine* engine, const char* request_json) {
  try {
    if (engine == nullptr || !engine->engine) {
      return copyString(voxon::dumpJson(voxon::errorResponse(voxon::errc::kInvalidRequest, "El motor está cerrado")));
    }
    if (request_json == nullptr) {
      return copyString(voxon::dumpJson(voxon::errorResponse(voxon::errc::kInvalidRequest, "La solicitud está vacía")));
    }
    return copyString(engine->engine->execute(std::string_view(request_json)));
  } catch (...) {
    return copyString(R"({"ok":false,"error":{"code":"internal_error","message":"Error inesperado"}})");
  }
}

void voxon_free(char* text) { std::free(text); }

void voxon_close(voxon_engine* engine) { delete engine; }
