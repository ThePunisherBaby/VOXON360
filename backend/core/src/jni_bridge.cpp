// Puente JNI para el servidor Java (clase com.voxon.core.NativeCore).
//
// Los textos viajan como byte[] en UTF-8 para no depender del "UTF-8
// modificado" de JNI, que altera emojis y otros caracteres.

#include <jni.h>

#include <string>

#include "voxon/voxon.h"

namespace {

std::string fromBytes(JNIEnv* env, jbyteArray array) {
  if (array == nullptr) {
    return {};
  }
  const jsize length = env->GetArrayLength(array);
  std::string text(static_cast<size_t>(length), '\0');
  env->GetByteArrayRegion(array, 0, length, reinterpret_cast<jbyte*>(text.data()));
  return text;
}

jbyteArray toBytes(JNIEnv* env, const char* text) {
  const auto length = static_cast<jsize>(std::char_traits<char>::length(text));
  jbyteArray array = env->NewByteArray(length);
  if (array != nullptr) {
    env->SetByteArrayRegion(array, 0, length, reinterpret_cast<const jbyte*>(text));
  }
  return array;
}

void throwIllegalState(JNIEnv* env, const char* message) {
  jclass type = env->FindClass("java/lang/IllegalStateException");
  if (type != nullptr) {
    env->ThrowNew(type, message);
  }
}

voxon_engine* handleOf(jlong handle) { return reinterpret_cast<voxon_engine*>(handle); }

}  // namespace

extern "C" {

JNIEXPORT jbyteArray JNICALL Java_com_voxon_core_NativeCore_version(JNIEnv* env, jclass) {
  return toBytes(env, voxon_version());
}

JNIEXPORT jlong JNICALL Java_com_voxon_core_NativeCore_open(JNIEnv* env, jclass, jbyteArray path,
                                                            jbyteArray options) {
  const auto pathText = fromBytes(env, path);
  const auto optionsText = fromBytes(env, options);
  char* error = nullptr;
  voxon_engine* engine = voxon_open_with_options(pathText.c_str(), optionsText.c_str(), &error);
  if (engine == nullptr) {
    throwIllegalState(env, error != nullptr ? error : "No se pudo abrir el motor");
    voxon_free(error);
    return 0;
  }
  return reinterpret_cast<jlong>(engine);
}

JNIEXPORT jbyteArray JNICALL Java_com_voxon_core_NativeCore_execute(JNIEnv* env, jclass, jlong handle,
                                                                    jbyteArray request) {
  const auto requestText = fromBytes(env, request);
  char* response = voxon_execute(handleOf(handle), requestText.c_str());
  if (response == nullptr) {
    throwIllegalState(env, "Sin memoria para la respuesta del motor");
    return nullptr;
  }
  jbyteArray result = toBytes(env, response);
  voxon_free(response);
  return result;
}

JNIEXPORT void JNICALL Java_com_voxon_core_NativeCore_close(JNIEnv*, jclass, jlong handle) {
  voxon_close(handleOf(handle));
}

}  // extern "C"
