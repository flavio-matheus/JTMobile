// Ponte C para o Flutter (dart:ffi): decodificação e codificação FT8/FT4 sobre a ft8_lib (MIT),
// espectro para a waterfall e reamostragem 48 kHz -> 12 kHz.
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ft8lib/common/monitor.h"
#include "ft8lib/fft/kiss_fftr.h"
#include "ft8lib/ft8/constants.h"
#include "ft8lib/ft8/decode.h"
#include "ft8lib/ft8/encode.h"
#include "ft8lib/ft8/message.h"

#ifdef __ANDROID__
#define FTX_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define FTX_EXPORT
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct
{
    float freq_hz;
    float dt_sec;
    float snr_db;
    int32_t score;
    char text[48];
} FtxDecoded; // 64 bytes

// ---------------------------------------------------------------- hash table de indicativos

#define CALL_HASH_SIZE 1024

static struct
{
    char callsign[12];
    uint32_t hash;
} g_calls[CALL_HASH_SIZE];

static void calls_cleanup(uint8_t max_age)
{
    for (int i = 0; i < CALL_HASH_SIZE; ++i)
    {
        if (g_calls[i].callsign[0] == '\0')
            continue;
        uint8_t age = (uint8_t)(g_calls[i].hash >> 24);
        if (age > max_age)
        {
            g_calls[i].callsign[0] = '\0';
            g_calls[i].hash = 0;
        }
        else
        {
            g_calls[i].hash = (((uint32_t)age + 1u) << 24) | (g_calls[i].hash & 0x3FFFFFu);
        }
    }
}

static void calls_add(const char* callsign, uint32_t hash)
{
    uint16_t hash10 = (hash >> 12) & 0x3FFu;
    int idx = (hash10 * 23) % CALL_HASH_SIZE;
    for (int tries = 0; tries < CALL_HASH_SIZE; ++tries)
    {
        if (g_calls[idx].callsign[0] == '\0')
            break;
        if (((g_calls[idx].hash & 0x3FFFFFu) == hash) && strcmp(g_calls[idx].callsign, callsign) == 0)
        {
            g_calls[idx].hash &= 0x3FFFFFu;
            return;
        }
        idx = (idx + 1) % CALL_HASH_SIZE;
    }
    strncpy(g_calls[idx].callsign, callsign, 11);
    g_calls[idx].callsign[11] = '\0';
    g_calls[idx].hash = hash;
}

static bool calls_lookup(ftx_callsign_hash_type_t type, uint32_t hash, char* callsign)
{
    uint8_t shift = (type == FTX_CALLSIGN_HASH_10_BITS) ? 12 : (type == FTX_CALLSIGN_HASH_12_BITS ? 10 : 0);
    uint16_t hash10 = (hash >> (12 - shift)) & 0x3FFu;
    int idx = (hash10 * 23) % CALL_HASH_SIZE;
    for (int tries = 0; tries < CALL_HASH_SIZE && g_calls[idx].callsign[0] != '\0'; ++tries)
    {
        if (((g_calls[idx].hash & 0x3FFFFFu) >> shift) == hash)
        {
            strcpy(callsign, g_calls[idx].callsign);
            return true;
        }
        idx = (idx + 1) % CALL_HASH_SIZE;
    }
    callsign[0] = '\0';
    return false;
}

static ftx_callsign_hash_interface_t g_hash_if = {.lookup_hash = calls_lookup, .save_hash = calls_add};

// ---------------------------------------------------------------- SNR

static int cmp_float(const void* a, const void* b)
{
    float x = *(const float*)a, y = *(const float*)b;
    return (x > y) - (x < y);
}

static inline float wf_power(const ftx_waterfall_t* wf, size_t idx)
{
    return powf(10.0f, WF_ELEM_MAG(wf->mag[idx]) * 0.1f);
}

// Estima o SNR (referência 2500 Hz, como o WSJT-X/JTDX) comparando a potência dos tons transmitidos
// com o ruído médio local (mediana corrigida) da waterfall.
static float estimate_snr(const ftx_waterfall_t* wf, const ftx_candidate_t* cand, const ftx_message_t* msg, bool ft4,
                          float symbol_period)
{
    const int nn = ft4 ? FT4_NN : FT8_NN;
    uint8_t tones[FT4_NN];
    if (ft4)
        ft4_encode(msg->payload, tones);
    else
        ft8_encode(msg->payload, tones);

    // Potência média nos tons corretos
    double psig = 0;
    int cnt = 0;
    for (int k = 0; k < nn; ++k)
    {
        int block = cand->time_offset + k;
        if (block < 0 || block >= wf->num_blocks)
            continue;
        // FT4 usa 4 tons; FT8 usa 8. A ordem dos símbolos transmitidos já é a de tons (0..N-1).
        int bin = cand->freq_offset + tones[k];
        if (bin < 0 || bin >= wf->num_bins)
            continue;
        size_t idx = ((((size_t)block * wf->time_osr + cand->time_sub) * wf->freq_osr + cand->freq_sub) * wf->num_bins) + bin;
        psig += wf_power(wf, idx);
        ++cnt;
    }
    if (cnt < nn / 2)
        return -30.0f;
    psig /= cnt;

    // Ruído: mediana da potência em ±50 bins ao redor, todos os blocos, sem sub-amostragem.
    int b0 = cand->freq_offset - 50, b1 = cand->freq_offset + 58;
    if (b0 < 0)
        b0 = 0;
    if (b1 > wf->num_bins)
        b1 = wf->num_bins;
    int nb = wf->num_blocks;
    int step = nb > 40 ? nb / 40 : 1;
    int cap = ((nb + step - 1) / step) * (b1 - b0 + 1);
    float* v = (float*)malloc(sizeof(float) * (size_t)(cap > 0 ? cap : 1));
    if (!v)
        return -30.0f;
    int n = 0;
    for (int blk = 0; blk < nb; blk += step)
    {
        for (int b = b0; b < b1; ++b)
        {
            size_t idx = ((((size_t)blk * wf->time_osr) * wf->freq_osr) * wf->num_bins) + b;
            v[n++] = wf_power(wf, idx);
        }
    }
    float pnoise = 1e-12f;
    if (n > 0)
    {
        qsort(v, n, sizeof(float), cmp_float);
        // percentil 25 (robusto a outros sinais na banda) -> media de uma distribuicao exponencial
        pnoise = v[n / 4] * 3.476f;
    }
    free(v);

    double ratio = psig / pnoise - 1.0;
    if (ratio < 1e-3)
        ratio = 1e-3;
    // ENBW (Hann, nfft = block * freq_osr) = 1.5 * (1 / (symbol_period * freq_osr)) Hz
    double enbw = 1.5 / (symbol_period * wf->freq_osr);
    double snr = 10.0 * log10(ratio) + 10.0 * log10(enbw / 2500.0);
    if (snr < -30.0)
        snr = -30.0;
    if (snr > 40.0)
        snr = 40.0;
    return (float)snr;
}

// ---------------------------------------------------------------- decodificação

#define MAX_CANDIDATES 200
#define MAX_UNIQUE 80

// protocol: 0 = FT8, 1 = FT4. Retorna o número de mensagens escritas em `out`.
FTX_EXPORT int ftx_decode(const float* samples, int num_samples, int sample_rate, int protocol, float f_min,
                          float f_max, int max_out, FtxDecoded* out)
{
    const bool ft4 = protocol == 1;
    const float slot = ft4 ? FT4_SLOT_TIME : FT8_SLOT_TIME;
    (void)slot;
    monitor_config_t cfg = {.f_min = f_min,
                            .f_max = f_max,
                            .sample_rate = sample_rate,
                            .time_osr = 2,
                            .freq_osr = 2,
                            .protocol = ft4 ? FTX_PROTOCOL_FT4 : FTX_PROTOCOL_FT8};
    monitor_t mon;
    monitor_init(&mon, &cfg);

    for (int pos = 0; pos + mon.block_size <= num_samples; pos += mon.block_size)
    {
        if (mon.wf.num_blocks >= mon.wf.max_blocks)
            break;
        monitor_process(&mon, samples + pos);
    }

    const ftx_waterfall_t* wf = &mon.wf;
    ftx_candidate_t cands[MAX_CANDIDATES];
    int ncand = ftx_find_candidates(wf, MAX_CANDIDATES, cands, 10);

    static ftx_message_t uniq[MAX_UNIQUE];
    int nuniq = 0;
    int nout = 0;

    for (int i = 0; i < ncand && nout < max_out; ++i)
    {
        const ftx_candidate_t* c = &cands[i];
        ftx_message_t msg;
        ftx_decode_status_t st;
        if (!ftx_decode_candidate(wf, c, 25, &msg, &st))
            continue;

        bool dup = false;
        for (int u = 0; u < nuniq; ++u)
        {
            if (uniq[u].hash == msg.hash && memcmp(uniq[u].payload, msg.payload, sizeof(msg.payload)) == 0)
            {
                dup = true;
                break;
            }
        }
        if (dup)
            continue;
        if (nuniq < MAX_UNIQUE)
            uniq[nuniq++] = msg;

        char text[FTX_MAX_MESSAGE_LENGTH];
        ftx_message_offsets_t offs;
        if (ftx_message_decode(&msg, &g_hash_if, text, &offs) != FTX_MESSAGE_RC_OK)
            continue;

        FtxDecoded* d = &out[nout++];
        memset(d, 0, sizeof(*d));
        d->freq_hz = (mon.min_bin + c->freq_offset + (float)c->freq_sub / wf->freq_osr) / mon.symbol_period;
        float t = (c->time_offset + (float)c->time_sub / wf->time_osr) * mon.symbol_period;
        d->dt_sec = t - 0.5f - 0.13f; // calibrado contra gravacoes de referencia do WSJT-X
        d->score = c->score;
        d->snr_db = estimate_snr(wf, c, &msg, ft4, mon.symbol_period);
        strncpy(d->text, text, sizeof(d->text) - 1);
    }

    calls_cleanup(10);
    monitor_free(&mon);
    return nout;
}

// ---------------------------------------------------------------- codificação / síntese

#define GFSK_CONST_K 5.336446f

static void gfsk_pulse(int n_spsym, float bt, float* pulse)
{
    for (int i = 0; i < 3 * n_spsym; ++i)
    {
        float t = i / (float)n_spsym - 1.5f;
        float a1 = GFSK_CONST_K * bt * (t + 0.5f);
        float a2 = GFSK_CONST_K * bt * (t - 0.5f);
        pulse[i] = (erff(a1) - erff(a2)) / 2;
    }
}

// Converte texto em tons (FT8: 79, FT4: 105). Retorna o nº de tons ou negativo em erro.
FTX_EXPORT int ftx_encode(const char* text, int protocol, uint8_t* tones)
{
    ftx_message_t msg;
    ftx_message_rc_t rc = ftx_message_encode(&msg, &g_hash_if, text);
    if (rc != FTX_MESSAGE_RC_OK)
        return -(int)rc - 1;
    if (protocol == 1)
    {
        ft4_encode(msg.payload, tones);
        return FT4_NN;
    }
    ft8_encode(msg.payload, tones);
    return FT8_NN;
}

// Sintetiza o sinal GFSK (amplitude 1.0) a `rate` Hz, f0 = frequência do tom 0.
// Retorna o nº de amostras escritas (n_sym * amostras_por_símbolo). `signal` deve ter espaço suficiente.
FTX_EXPORT int ftx_synth(const uint8_t* tones, int protocol, float f0, int rate, float* signal)
{
    const bool ft4 = protocol == 1;
    const int n_sym = ft4 ? FT4_NN : FT8_NN;
    const float period = ft4 ? FT4_SYMBOL_PERIOD : FT8_SYMBOL_PERIOD;
    const float bt = ft4 ? 1.0f : 2.0f;
    const int n_spsym = (int)(0.5f + rate * period);
    const int n_wave = n_sym * n_spsym;
    const float dphi_peak = 2 * (float)M_PI / n_spsym;

    float* dphi = (float*)malloc(sizeof(float) * (size_t)(n_wave + 2 * n_spsym));
    float* pulse = (float*)malloc(sizeof(float) * (size_t)(3 * n_spsym));
    if (!dphi || !pulse)
    {
        free(dphi);
        free(pulse);
        return -1;
    }
    for (int i = 0; i < n_wave + 2 * n_spsym; ++i)
        dphi[i] = 2 * (float)M_PI * f0 / rate;
    gfsk_pulse(n_spsym, bt, pulse);
    for (int i = 0; i < n_sym; ++i)
    {
        int ib = i * n_spsym;
        for (int j = 0; j < 3 * n_spsym; ++j)
            dphi[j + ib] += dphi_peak * tones[i] * pulse[j];
    }
    for (int j = 0; j < 2 * n_spsym; ++j)
    {
        dphi[j] += dphi_peak * pulse[j + n_spsym] * tones[0];
        dphi[j + n_sym * n_spsym] += dphi_peak * pulse[j] * tones[n_sym - 1];
    }
    float phi = 0;
    for (int k = 0; k < n_wave; ++k)
    {
        signal[k] = sinf(phi);
        phi = fmodf(phi + dphi[k + n_spsym], 2 * (float)M_PI);
    }
    int n_ramp = n_spsym / 8;
    for (int i = 0; i < n_ramp; ++i)
    {
        float env = (1 - cosf(2 * (float)M_PI * i / (2 * n_ramp))) / 2;
        signal[i] *= env;
        signal[n_wave - 1 - i] *= env;
    }
    free(dphi);
    free(pulse);
    return n_wave;
}

// ---------------------------------------------------------------- espectro (waterfall)

// Calcula o espectro de potência em dB (janela de Hann) de `nfft` amostras de 12 kHz.
// Escreve nfft/2 valores em `out_db` (bin k = k * 12000 / nfft Hz). Retorna nfft/2.
FTX_EXPORT int ftx_spectrum(const float* samples, int nfft, float* out_db)
{
    size_t work = 0;
    kiss_fftr_alloc(nfft, 0, NULL, &work);
    void* mem = malloc(work);
    kiss_fftr_cfg cfg = kiss_fftr_alloc(nfft, 0, mem, &work);
    float* in = (float*)malloc(sizeof(float) * (size_t)nfft);
    kiss_fft_cpx* fo = (kiss_fft_cpx*)malloc(sizeof(kiss_fft_cpx) * (size_t)(nfft / 2 + 1));
    if (!mem || !cfg || !in || !fo)
    {
        free(mem);
        free(in);
        free(fo);
        return -1;
    }
    for (int i = 0; i < nfft; ++i)
    {
        float s = sinf((float)M_PI * i / nfft);
        in[i] = samples[i] * s * s * (2.0f / nfft);
    }
    kiss_fftr(cfg, in, fo);
    for (int k = 0; k < nfft / 2; ++k)
        out_db[k] = 10.0f * log10f(1e-12f + fo[k].r * fo[k].r + fo[k].i * fo[k].i);
    free(mem);
    free(in);
    free(fo);
    return nfft / 2;
}

// ---------------------------------------------------------------- reamostragem 48 k -> 12 k

#define DEC_TAPS 64

// Estado do decimador. `hist` é um buffer circular "escrito duas vezes" (posição i e i+DEC_TAPS),
// o que permite ler sempre uma janela contígua de DEC_TAPS amostras sem mover memória.
typedef struct
{
    float hist[2 * DEC_TAPS];
    int pos;   // próxima posição de escrita (0..DEC_TAPS-1)
    int phase; // contador 0..3 para decimar por 4
} Dec4State;

static float g_dec_coef[DEC_TAPS];
static bool g_dec_ready = false;

static void dec_init(void)
{
    // passa-baixas por janelas de Hamming, corte 5 kHz @ 48 kHz
    const double fc = 5000.0 / 48000.0;
    double sum = 0;
    for (int i = 0; i < DEC_TAPS; ++i)
    {
        double m = i - (DEC_TAPS - 1) / 2.0;
        double sinc = (fabs(m) < 1e-9) ? 2 * M_PI * fc : sin(2 * M_PI * fc * m) / m;
        double w = 0.54 - 0.46 * cos(2 * M_PI * i / (DEC_TAPS - 1));
        g_dec_coef[i] = (float)(sinc * w);
        sum += g_dec_coef[i];
    }
    for (int i = 0; i < DEC_TAPS; ++i)
        g_dec_coef[i] = (float)(g_dec_coef[i] / sum);
    g_dec_ready = true;
}

FTX_EXPORT void* ftx_dec4_new(void)
{
    if (!g_dec_ready)
        dec_init();
    return calloc(1, sizeof(Dec4State));
}

FTX_EXPORT void ftx_dec4_free(void* st)
{
    free(st);
}

// Entrada: PCM 16 bit mono 48 kHz. Saída: float [-1,1] a 12 kHz. Retorna nº de amostras de saída.
FTX_EXPORT int ftx_dec4(void* state, const int16_t* in, int n, float* out)
{
    Dec4State* s = (Dec4State*)state;
    int nout = 0;
    for (int i = 0; i < n; ++i)
    {
        const float x = in[i] / 32768.0f;
        s->hist[s->pos] = x;
        s->hist[s->pos + DEC_TAPS] = x;
        s->pos = (s->pos + 1) % DEC_TAPS;
        if (++s->phase == 4)
        {
            s->phase = 0;
            // janela contígua: da amostra mais antiga (hist[pos]) até a mais nova
            const float* w = s->hist + s->pos;
            float acc = 0;
            for (int k = 0; k < DEC_TAPS; ++k)
                acc += w[k] * g_dec_coef[DEC_TAPS - 1 - k];
            out[nout++] = acc;
        }
    }
    return nout;
}
