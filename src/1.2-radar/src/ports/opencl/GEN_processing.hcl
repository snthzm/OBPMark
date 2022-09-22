
std::string kernel_code = 
"/* ATOMIC operations */\n"
"//ADD\n"
"inline void atomicAdd_f(volatile __global float *addr, float val)\n"
"{\n"
"union {\n"
"unsigned int u32;\n"
"float f32;\n"
"} next, expected, current;\n"
"current.f32 = *addr;\n"
"do {\n"
"expected.f32 = current.f32;\n"
"next.f32 = expected.f32 + val;\n"
"current.u32 = atomic_cmpxchg( (volatile __global unsigned int *)addr, expected.u32, next.u32);\n"
"} while( current.u32 != expected.u32 );\n"
"}\n"
"//MIN\n"
"inline void atomicMin_f(volatile __global float *addr, float val)\n"
"{\n"
"union {\n"
"unsigned int u32;\n"
"float f32;\n"
"} next, expected, current;\n"
"current.f32 = *addr;\n"
"do {\n"
"expected.f32 = current.f32;\n"
"next.f32 = min(expected.f32, val);\n"
"current.u32 = atomic_cmpxchg( (volatile __global unsigned int *)addr, expected.u32, next.u32);\n"
"} while( current.u32 != expected.u32 );\n"
"}\n"
"//MAX\n"
"inline void atomicMax_f(volatile __global float *addr, float val)\n"
"{\n"
"union {\n"
"unsigned int u32;\n"
"float f32;\n"
"} next, expected, current;\n"
"current.f32 = *addr;\n"
"do {\n"
"expected.f32 = current.f32;\n"
"next.f32 = max(expected.f32, val);\n"
"current.u32 = atomic_cmpxchg( (volatile __global unsigned int *)addr, expected.u32, next.u32);\n"
"} while( current.u32 != expected.u32 );\n"
"}\n"
"/* COMPLEX number support */\n"
"typedef float2 cfloat;\n"
"inline cfloat cmul(cfloat a, cfloat b){\n"
"return (cfloat) (a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);\n"
"}\n"
"inline cfloat conj(cfloat a){\n"
"return (cfloat) (a.x, -a.y);\n"
"}\n"
"inline cfloat polar1(float th){\n"
"return (cfloat) (cos(th), sin(th));\n"
"}\n"
"inline float cabs(cfloat a){\n"
"return sqrt(a.x * a.x + a.y * a.y);\n"
"}\n"
"inline float arg(cfloat a){\n"
"if(a.x > 0){\n"
"return atan(a.y / a.x);\n"
"}else if(a.x < 0 && a.y >= 0){\n"
"return atan(a.y / a.x) + M_PI;\n"
"}else if(a.x < 0 && a.y < 0){\n"
"return atan(a.y / a.x) - M_PI;\n"
"}else if(a.x == 0 && a.y > 0){\n"
"return M_PI/2;\n"
"}else if(a.x == 0 && a.y < 0){\n"
"return -M_PI/2;\n"
"}else{\n"
"return 0;\n"
"}\n"
"}\n"
"/* OPENCL kernels */\n"
"static global float fDc = 0;\n"
"static global float v_max = FLT_MIN;\n"
"static global float v_min = FLT_MAX;\n"
"const float pi = (float) M_PI;      //PI\n"
"const float c = (float) 299792458;  //speed of light\n"
"inline unsigned int next_power_of2(unsigned int n)\n"
"{\n"
"unsigned int v = n;\n"
"v--;\n"
"v |= v >> 1;\n"
"v |= v >> 2;\n"
"v |= v >> 4;\n"
"v |= v >> 8;\n"
"v |= v >> 16;\n"
"v++;\n"
"return v;\n"
"}\n"
"void kernel\n"
"SAR_range_ref(global float *rrf,  const unsigned int rsize, const float fs, const float slope, const unsigned int nit)\n"
"{\n"
"cfloat *c_ref = (cfloat*) rrf;\n"
"int i = get_global_id(0);\n"
"if (i >= rsize || i >= nit) return;\n"
"float phase = (-((float)nit)/2+i) * 1/fs;\n"
"phase = pi * slope * phase * phase;\n"
"c_ref[i] = polar1(phase);\n"
"}\n"
"void kernel\n"
"SAR_DCE(global const float *data, const unsigned int apatch, const unsigned int rsize, const float const_k, local cfloat *tmp)\n"
"{\n"
"unsigned int i = get_local_id(0);\n"
"if(i >= (apatch-1)) return;\n"
"unsigned int j = get_group_id(0);\n"
"int k = get_num_groups(0);\n"
"unsigned int width = rsize;\n"
"unsigned int off = next_power_of2(width);\n"
"unsigned int cell_x_thread = ceil((float) apatch/get_local_size(0));\n"
"cfloat *c_data = (cfloat*) data;\n"
"tmp[i] = cmul(conj(c_data[i*off+j]), c_data[(i+1)*off+j]);\n"
"for(int k = 1; k < cell_x_thread; k++){\n"
"int l = i + get_local_size(0) * k;\n"
"if (l < apatch-1) tmp[i] += cmul(conj(c_data[l*off+j]), c_data[(l+1)*off+j]);\n"
"}\n"
"barrier(CLK_LOCAL_MEM_FENCE);\n"
"for (int s = get_local_size(0)/2; s > 0; s >>= 1){\n"
"if (i < s) tmp[i] += tmp[i+s];\n"
"barrier(CLK_LOCAL_MEM_FENCE);\n"
"}\n"
"if (i == 0){\n"
"float val = arg(tmp[0]);\n"
"val = val*const_k;\n"
"atomicAdd_f(&fDc, val);\n"
"barrier(CLK_GLOBAL_MEM_FENCE);\n"
"}\n"
"}\n"
"void kernel\n"
"printfDc()\n"
"{\n"
"printf(\"fDc: %f\\n\", fDc);\n"
"}\n"
"void kernel\n"
"SAR_rcmc_table(global unsigned int *offsets, const unsigned int apatch, const unsigned int avalid, const float PRF, const float lambda, const float vr, const float ro, const float fs)\n"
"{\n"
"unsigned int i = get_global_id(1);\n"
"unsigned int j = get_global_id(0);\n"
"float delta, offset;\n"
"unsigned int ind;\n"
"unsigned int width = apatch;\n"
"delta = j * (PRF/avalid) + fDc;\n"
"offset = (1/sqrt(1-pow(lambda * delta / (2 * vr), 2))-1) * (ro + i * (c/(2*fs)));\n"
"offset = round (offset / (c/(2*fs))) * width;\n"
"ind = i * width + j;\n"
"offsets[ind] = ind + offset;\n"
"}\n"
"void kernel\n"
"SAR_azimuth_ref(global float *arf, const float ro, const float fs, const float lambda, const float vr, const float PRF, const unsigned int rvalid, const unsigned int apatch)\n"
"{\n"
"float  rnge = ro+(rvalid/2)*(c/(2*fs));        //range perpendicular to azimuth\n"
"float  rdc = rnge/sqrt(1-pow(lambda*fDc/(2*vr),2));    //squinted range\n"
"float  tauz = (rdc*(lambda/10) * 0.8) / vr;            //Tau in the azimuth\n"
"float  chirp = -(2*vr*vr)/lambda/rdc;          //Azimuth chirp rate\n"
"int    nit = floor(tauz * PRF);\n"
"cfloat *c_ref = (cfloat*) arf;\n"
"int i = get_global_id(0);\n"
"if (i >= apatch || i >= nit) return;\n"
"float phase = (-((float)nit)/2+i) * 1/PRF;\n"
"phase = 2 * pi * fDc * phase + pi * chirp * phase * phase;\n"
"c_ref[i] = polar1(phase);\n"
"}\n"
"void kernel\n"
"SAR_ref_product(global float *data, global float *ref, const unsigned int w, const unsigned int h)\n"
"{\n"
"unsigned int i = get_global_id(1); if (i >= h) return;\n"
"unsigned int j = get_global_id(0); if (j >= w) return;\n"
"i = i + h * get_global_id(2); //Add to i the patch offset\n"
"cfloat *c_data = (cfloat*) data;\n"
"cfloat *c_ref = (cfloat*) ref;\n"
"c_data[i*w+j] = cmul(conj(c_ref[j]), c_data[i*w+j]);\n"
"}\n"
"void kernel\n"
"SAR_transpose(global float *in, global float *out, unsigned int in_width, unsigned int out_width, unsigned int nrows, unsigned int ncols)\n"
"{\n"
"unsigned int i = get_global_id(1); if (i >= nrows) return;\n"
"unsigned int j = get_global_id(0); if (j >= ncols) return;\n"
"unsigned int k = get_global_id(2);\n"
"out[2*((j+ncols*k)*out_width+i)]   = in[2*((i + nrows * k) * in_width +j)];\n"
"out[2*((j+ncols*k)*out_width+i)+1] = in[2*((i + nrows * k) * in_width +j)+1];\n"
"}\n"
"void kernel\n"
"SAR_rcmc(global float *data, global unsigned int *offsets, unsigned int width, unsigned int height)\n"
"{\n"
"unsigned int i = get_global_id(1);\n"
"unsigned int j = get_global_id(0);\n"
"unsigned int k = get_global_id(2);\n"
"cfloat *c_data = &((cfloat*) data)[(i+k*height) * width];\n"
"unsigned int ind = i * width + j;\n"
"if (offsets[ind] < (height * width)) c_data[ind] = c_data[offsets[ind]];\n"
"}\n"
"void kernel\n"
"SAR_multilook(global float *radar_data, global float *image, const unsigned int rvalid, const unsigned int asize, const unsigned int rsize, const unsigned int npatch, const unsigned int apatch, unsigned int width, unsigned int height)\n"
"{\n"
"cfloat *c_data = (cfloat*) radar_data;\n"
"unsigned int isx = rvalid/width;\n"
"unsigned int isy = asize/width;\n"
"unsigned int range_w = next_power_of2(rsize);\n"
"int x = get_global_id(1); //if (x >= width) return;\n"
"int y = get_global_id(0); //if (y >= height) return;\n"
"unsigned int oIdx = y * width + x;\n"
"unsigned int row_x_patch = height/npatch;\n"
"unsigned int patch = y / row_x_patch;\n"
"unsigned int patch_offset = patch * apatch * range_w;\n"
"unsigned int initIdx = patch_offset + (y%row_x_patch * isy) * range_w + (x * isx);\n"
"float value;\n"
"float fimg = 0;\n"
"for(int iy = 0; iy < isy; iy++)\n"
"for(int jx = 0; jx < isx; jx++)\n"
"fimg += cabs(c_data[initIdx+iy*range_w+jx]);\n"
"value = fimg/(isx*isy);\n"
"value = (value == 0)?0:log2(value);\n"
"image[oIdx] = value;\n"
"atomicMax_f(&v_max, value);\n"
"barrier(CLK_GLOBAL_MEM_FENCE);\n"
"atomicMin_f(&v_min, value);\n"
"barrier(CLK_GLOBAL_MEM_FENCE);\n"
"}\n"
"void kernel\n"
"quantize(global float *data, global unsigned char *image, const unsigned int width, const unsigned int height)\n"
"{\n"
"float scale = 256.f / (v_max-v_min);\n"
"int x = get_global_id(1); if(x >= width) return;\n"
"int y = get_global_id(0); if(y >= height) return;\n"
"image[y*width+x] = min(255.f,floor(scale * (data[y*width+x]-v_min)));\n"
"}\n"
"//FFT\n"
"void fft_kernel(global float *data, const int nn, const int isign){\n"
"int n, mmax, m, j, istep, i;\n"
"float wtemp, wr, wpr, wpi, wi, theta;\n"
"float tempr, tempi;\n"
"float swp;\n"
"// reverse-binary reindexing\n"
"n = nn<<1;\n"
"j=1;\n"
"for (i=1; i<n; i+=2) {\n"
"if (j>i) {\n"
"swp = data[j-1];\n"
"data[j-1] = data[i-1];\n"
"data[i-1] = swp;\n"
"swp = data[j];\n"
"data[j] = data[i];\n"
"data[i] = swp;\n"
"}\n"
"m = nn;\n"
"while (m>=2 && j>m) {\n"
"j -= m;\n"
"m >>= 1;\n"
"}\n"
"j += m;\n"
"};\n"
"// here begins the Danielson-Lanczos section\n"
"mmax=2;\n"
"while (n>mmax) {\n"
"istep = mmax<<1;\n"
"theta = -(2*(float)M_PI/(mmax*isign));\n"
"wtemp = sin(0.5*theta);\n"
"wpr = -2.0*wtemp*wtemp;\n"
"wpi = sin(theta);\n"
"wr = 1.0;\n"
"wi = 0.0;\n"
"for (m=1; m < mmax; m += 2) {\n"
"for (i=m; i <= n; i += istep) {\n"
"j=i+mmax;\n"
"tempr = wr*data[j-1] - wi*data[j];\n"
"tempi = wr * data[j] + wi*data[j-1];\n"
"data[j-1] = data[i-1] - tempr;\n"
"data[j] = data[i] - tempi;\n"
"data[i-1] += tempr;\n"
"data[i] += tempi;\n"
"}\n"
"wtemp=wr;\n"
"wr += wr*wpr - wi*wpi;\n"
"wi += wi*wpr + wtemp*wpi;\n"
"}\n"
"mmax=istep;\n"
"}\n"
"}\n"
"void kernel\n"
"fft(global float* data, const int nn){\n"
"unsigned int i=get_global_id(0);\n"
"fft_kernel(&data[i*nn*2], nn, 1);\n"
"}\n"
"void kernel\n"
"ifft(global float* data, const int nn){\n"
"unsigned int i=get_global_id(0);\n"
"fft_kernel(&data[i*nn*2], nn, -1);\n"
"}\n"
;
