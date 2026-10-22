// pa-vulkan.h - Vulkan Compute Attention Engine for Android & PC Host.
// Offloads attention computation over 128k+ long context KV pages to Vulkan-capable GPUs
// (Adreno 6xx/7xx/8xx, Mali-Gxx, Immortalis, NVIDIA, AMD, Intel).
//
// Replaces Apple Metal (pa-metal.mm) and Apple Neural Engine (pa-ane.mm) with standard Vulkan Compute.
#pragma once

#include "phone-attn.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace pa {

class vulkan_engine : public engine {
public:
    std::string error;
    std::string device_name = "Vulkan Compute Device";
    uint32_t api_version = 0;
    size_t total_vram_mb = 0;

    vulkan_engine();
    virtual ~vulkan_engine();

    bool init();
    std::string describe() override;

    bool alloc_page(size_t bytes, page & p) override;
    void free_page(page & p) override;

    bool begin(const page * pages, const uint32_t * nkeys, int n_pages,
               const uint16_t * Qs, const config_req & cfg, int ng = 1) override;

    double end(float * O, float * m, float * l) override;

    void warm() override;
    double exec_ms() const override { return last_exec_ms_; }
    void arm(const page * pages, const uint32_t * nkeys, int n_pages,
             const config_req & cfg, int ntok) override;

private:
    struct vk_ctx;
    std::unique_ptr<vk_ctx> vk_;
    double last_exec_ms_ = 0.0;
    std::chrono::high_resolution_clock::time_point t_start_;

    // In-flight execution buffers
    std::vector<float> pending_O_;
    std::vector<float> pending_m_;
    std::vector<float> pending_l_;
    bool in_flight_ = false;
    std::mutex mu_;
};

} // namespace pa
