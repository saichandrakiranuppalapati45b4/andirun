#include <jni.h>
#include <string>
#include <memory>
#include <thread>
#include <atomic>

#include "llama.h"
#include "tools/split-prefill/tail-server.h"

static std::unique_ptr<spt::tail_server> g_server;
static spt::server_status g_status;
static std::atomic<bool> g_running{false};

extern "C" JNIEXPORT jint JNICALL
Java_com_andirun_worker_WorkerService_startTailServer(JNIEnv *env, jclass, jint port, jstring modelPath) {
    const char *path = env->GetStringUTFChars(modelPath, nullptr);
    std::string model_path_str(path);
    env->ReleaseStringUTFChars(modelPath, path);

    llama_backend_init();
    
    g_server = std::make_unique<spt::tail_server>(
        model_path_str,
        &g_status,
        [](const std::string &log_msg) {
            // Log to Android logcat
        }
    );

    std::string err = g_server->load();
    if (!err.empty()) {
        return -1;
    }

    g_running = true;
    std::string serve_err = g_server->serve(port);
    g_running = false;
    return serve_err.empty() ? 0 : -2;
}

extern "C" JNIEXPORT void JNICALL
Java_com_andirun_worker_WorkerService_stopTailServer(JNIEnv *, jclass) {
    g_running = false;
    // Server teardown
    g_server.reset();
    llama_backend_free();
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_andirun_worker_WorkerService_getWorkerStatus(JNIEnv *env, jclass) {
    std::lock_guard<std::mutex> lk(g_status.mu);
    std::string info = "State: " + g_status.state + 
                       " | Chunks: " + std::to_string(g_status.chunks) +
                       " | Tokens: " + std::to_string(g_status.tokens) +
                       " | LastTokS: " + std::to_string(g_status.last_tok_s);
    return env->NewStringUTF(info.c_str());
}
