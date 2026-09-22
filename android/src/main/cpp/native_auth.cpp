#include <jni.h>
#include <cstdlib>
#include <cstring>
#include <mutex>

static JavaVM* vm = nullptr;
static jclass plugin = nullptr;
static jmethodID requestMethod = nullptr;
static std::mutex mutex;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* value, void*) {
    vm = value;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_tayormi_native_1auth_NativeAuthPlugin_initializeNative(JNIEnv* env, jclass type) {
    std::lock_guard<std::mutex> guard(mutex);
    if (!plugin) {
        plugin = static_cast<jclass>(env->NewGlobalRef(type));
        requestMethod = env->GetStaticMethodID(type, "request", "([B)[B");
    }
}

extern "C" __attribute__((visibility("default"))) char* DnauthRequest(const char* input) {
    std::lock_guard<std::mutex> guard(mutex);
    const char* failure = "{\"state\":\"done\",\"status\":\"nativeError\",\"platformCode\":\"jni_unavailable\"}";
    if (!vm || !plugin || !requestMethod || !input) return strdup(failure);
    JNIEnv* env = nullptr;
    bool attached = false;
    jint state = vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (state == JNI_EDETACHED) {
        if (vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return strdup(failure);
        attached = true;
    } else if (state != JNI_OK) return strdup(failure);
    char* output = nullptr;
    if (env->PushLocalFrame(8) == JNI_OK) {
        const auto length = static_cast<jsize>(strlen(input));
        jbyteArray bytes = env->NewByteArray(length);
        if (bytes) {
            env->SetByteArrayRegion(bytes, 0, length, reinterpret_cast<const jbyte*>(input));
            if (!env->ExceptionCheck()) {
                auto response = static_cast<jbyteArray>(env->CallStaticObjectMethod(plugin, requestMethod, bytes));
                if (!env->ExceptionCheck() && response) {
                    const auto size = env->GetArrayLength(response);
                    output = static_cast<char*>(malloc(static_cast<size_t>(size) + 1));
                    if (output) {
                        env->GetByteArrayRegion(response, 0, size, reinterpret_cast<jbyte*>(output));
                        output[size] = '\0';
                    }
                }
            }
        }
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            free(output); output = nullptr;
        }
        env->PopLocalFrame(nullptr);
    } else if (env->ExceptionCheck()) env->ExceptionClear();
    if (attached) vm->DetachCurrentThread();
    return output ? output : strdup(failure);
}

extern "C" __attribute__((visibility("default"))) void DnauthFree(char* value) { free(value); }
