module main

import os
import log
import flag
import time
import rand

import vcp
import vcp.curlv

// host/nix-channels/
const nixst_ustc = "https://mirrors.ustc.edu.cn" // many 404
const nixst_tuna = "https://mirrors.tuna.tsinghua.edu.cn" // many 403
const nixst_sjtu = "https://mirrors.sjtug.sjtu.edu.cn" // many noresp
const nixst_nju = "https://mirror.nju.edu.cn"
const nixst_sustech = "https://mirrors.sustech.edu.cn"
// const hosturl = "https://cache.nixos.org"
// const chanurl = hosturl+"/nix-channels"
// const pkgsurl = chanurl+"/nixpkgs-24.05-darwin"
// const pkgsurl = chanurl+"/nixpkgs-unstable"
// how get this url by store path???
// nar pkg url: https://mirrors.ustc.edu.cn/nix-channels/store/nar/1b46dbba8m1dax0baqcnfwqvxah9h93hj638kf1l3jv0i2yqw123.nar.xz
// https://nix.dev/manual/nix/2.24/store/store-path#:~:text=To%20make%20store%20objects%20accessible%20to%20operating%20system,Base32%20%2820%20arbitrary%20bytes%20become%2032%20ASCII%20characters%29
// https://mirrors.ustc.edu.cn/nix-channels/store/nix-cache-info
// nix nar
// narinfo
// https://mirrors.ustc.edu.cn/nix-channels/store/w5v7c0ikm6mzf17f3zyjvf0cn8gcammm.narinfo
// build log, brotli 压缩格式
// https://cache.nixos.org/log/4dslsa36jhy55szw3xgwzxa6k08bz3z1-pstree-2.39.drv

struct Nixbase {
	pub mut:
	hosturl string

	stpath string

    // $HOME/pacman/{temp,packages,sources,unnar,meta}
    // .narinfo => sources/
    // .nar.xz => sources/
    // store => sources/
	metadir string
	tempdir string
    unnardir string
	packdir string    
    srcdir string
}
pub fn Nixbase.new(hosturl ...string) Nixbase {
	mut me := Nixbase{hosturl: firstofv(hosturl)}
	// home := 
    hosturls := [nixst_sjtu, nixst_tuna, nixst_ustc, nixst_nju, nixst_sustech]
    if hosturl.len==0 {
        me.hosturl = hosturls[rand.int()%hosturls.len]
    }
    basedir := os.home_dir() + "/pacman"
    me.metadir = basedir + "/meta"
    me.tempdir = basedir + "/temp"
    me.unnardir = basedir + "/unnar"
    me.packdir = basedir + "/packages"    
    me.srcdir = basedir + "/sources"

	return me
}
pub fn (me Nixbase) chanurl() string { return me.hosturl + "/nix-channels/"}
// pub fn (me Nixbase) pkgurl() string { return me.chanurl() + "nixpkgs-24.05-darwin/" }
pub fn (me Nixbase) pkgurl() string { return me.chanurl() + "nixpkgs-unstable/" }
pub fn (me Nixbase) storeurl() string { return me.chanurl() + "store/" }
// 这个文件是什么格式？和 jq 相关，怎么解？
// https://github.com/NixOS/nixpkgs/blob/63c4c8d6d77f80f6bee07672bdcfd8d6180fdd92/pkgs/top-level/make-tarball.nix#L54
// brotli 压缩/解压命令？这是什么格式？？？
pub fn (me Nixbase) pkgjson_url() string { return me.pkgurl() + "packages.json.br" }
pub fn (me Nixbase) store_path_url() string { return me.pkgurl() + "store-paths.xz" }
// 这个文件对应哪个目录？~/.nix-defexpr/channels/nixpkgs/pkgs/
pub fn (me Nixbase) exprurl() string { return me.pkgurl() + "nixexprs.tar.xz" }
// /nix/store/w5v7c0ikm6mzf17f3zyjvf0cn8gcammm-xxx =>
// host///mirrors.ustc.edu.cn/nix-channels/store/w5v7c0ikm6mzf17f3zyjvf0cn8gcammm.narinfo
pub fn (me Nixbase) store_path_tonarurl(stpath string) string {
	hsval, pkg, ver := parse_nixstore_line(stpath)
	return me.chanurl() + "store/${hsval}.narinfo"
}
pub fn (mut me Nixbase) set_stpath(stpath string) { me.stpath = stpath }
// 在store/目录下的包名叫什么？？？
// eg: nix copy -vvv /nix/store/7wpfn219p67x4i00ll2widi9bm2ysa82-pstree-2.39 --to tmpdir/  --impure --no-use-registries --no-update-lock-file --no-write-lock-file --no-recursive --refresh --repair
// 如何得到包的大小？？？需要看nix copy怎么实现的！！！
// 替换 DEPEND 中的库路径
// 查找依赖包
// copy下来的文件不能修改的问题，需要root？

pub fn (mut me Nixbase) sync_meta() {

}

pub fn (mut me Nixbase) fetch_narinfo(stpath string) Narinfo {
	mut ch := curlv.new().useragent("nix/2.21")
	ch.url(me.store_path_tonarurl(stpath))
	res := ch.get() or { panic(err) }
	vcp.info(res.stcode, res.data.len, stpath)

	return parse_narinfo(res.data)
}

// key: value format
fn parse_narinfo(scc string) Narinfo {
	mut narval := Narinfo{}
	lines := scc.split_into_lines()
	for line in lines {
		fields := line.split(": ")
		match fields[0] {
			"StorePath" {narval.store_path=fields[1]}
			"URL" {narval.relative_url=fields[1]}
			"Compression" {narval.compression=fields[1]}
			"FileHash" {narval.file_hash=fields[1]}
			"FileSize" {narval.file_size=fields[1].i64()}
			"NarHash" {narval.nar_hash=fields[1]}
			"NarSize" {narval.nar_size=fields[1].i64()}
			"References" {narval.references=fields[1].split(" ")}
			"Deriver" {narval.deriver=fields[1]}
			"Sig" {narval.signt=fields[1]}
			else{vcp.info("notcap", fields.str())}
		}
	}
	return narval
}

// eg.: https://mirrors.ustc.edu.cn/nix-channels/store/w5v7c0ikm6mzf17f3zyjvf0cn8gcammm.narinfo 
pub struct Narinfo {
	pub mut:
	store_path string
	relative_url string // nar/wthash.nar.xz
	compression string // xz, ...
	file_hash string // hashtype:hashvalue
	file_size i64
	nar_hash string  // hashtype:hashvalue
	nar_size i64
	references []string // depeneds store path, no /nix/store prefix
	deriver string // .drv?
	signt string
}


/////
pub fn runcmdv(cmd string, wkdir ... string) ([]string, bool) {
	return vcp.runcmdv(cmd, ...wkdir)
}

// todo pipe out or hang somewhere when too many out
pub fn runcmd(cmd string, wkdir string, capio bool) (string, bool) {
	return vcp.runcmd(cmd, wkdir, capio)
}

@[xdoc: 'My application that does X']
@[footer: 'A footer']
@[version: '1.2.3']
@[name: 'app']
struct Cmdarg {
    pub mut:
    show_version bool @[short: v; xdoc: 'Show version and exit']
    debug_level  int  @[long: debug; short: d; xdoc: 'Debug level']
    level        f32  @[only: l; xdoc: 'This doc text is overwritten']
    example      string
    square       bool
    show_help    bool   @[long: help; short: h]
    multi        int    @[only: m; repeats]
    wroom        []int  @[short: w]
    ignore_me    string @[ignore]

    // used
    stpath       bool   @[xdoc: "specify exact store path/package"]
    stname   string @[xdoc: "store host's name. nixos/ustc/tuna/nju..."]
    store    string @[xdoc: "store full url"]
    excepts      []string @[xdoc: "filter except words, like grep -v"]
}

// todo temp repack directory
// todo depends packages resolve
// linked shared library resolve
// todo remove share/man/info file
// todo max candidate lines to show option
// todo meta data file auto update
// todo implement nix copy, drop nix depened
// todo rootless mode, specifiy package install base
// todo specifiy nix channel version
// todo avoid nix copy depeneds
// todo package merge, bin/lib/man/info...
// todo order candidate store path, prefix, suffix...
// prerequires: sudo!!! tar brotli grep install_name_tool
// sometimes need select package.
// sometimes need input root password
fn main() {
	// mut fp := flag.new_flag_parser(os.args)
	// fp.string("xxx", 0, "uuu", "eee", flag.FlagConfig{})
	// fp.usage()
	cfg, nomats := flag.to_struct[Cmdarg](os.args, skip:1)!
	vcp.info(nomats.str())
	if cfg.show_help || true {
		doc := flag.to_doc[Cmdarg]()!
		// println(doc)
	}
	// dump(cfg)

	println('Hello World! ${os.args}, ${nomats}')
	// if true { return }

	args := nomats
	pkgname := args[0]
    mut rcvals := []string{}
    mut ino := -1

    if cfg.stpath {
        rcvals << pkgname
        ino = 0
    }else{
	// store_path_file := "store-path-head200" // about 15K
	// store_path_file := "store-path" // about 11M, stable 24.05
	store_path_file := "store-paths" // about 24M, unstable

	vcp.info("reading store-path maybe need secs...")
	rcvals = get_match_store_paths(store_path_file, pkgname)
	vcp.info(rcvals.len, rcvals.str().elide_right(64))
	vcp.zeroprt(rcvals.len, "not found", pkgname, os.file_size(store_path_file))
	if rcvals.len == 0 {
		exit(-1)
	}
	
	// todo filter by binarch

	maxoptno := 30
	for i, line in rcvals {
		vcp.info(i.str(), "\t", line.clone())
		if i > maxoptno { break}
	}
	vcp.trueprt(rcvals.len>maxoptno, "too many matches", rcvals.len, pkgname, "file size:", os.file_size(store_path_file))
	if rcvals.len > maxoptno {
		exit(-1)
	}

	mut ipt := ""
	if rcvals.len > 1 {
		ipt = os.input("input the no in [0,${rcvals.len-1}] > ")
		// vcp.info(ipt, ipt.is_digit())
		vcp.zeroprt(ipt, "no input any no")
		if ipt == "" || !ipt.is_digit() {}
		else {ino = ipt.int()}
	}else if rcvals.len == 1{
		vcp.info("only 1 skip interact selection.")
		time.sleep(time.second)
		ino = 0
	}
	// vcp.info(ino)
	if ino < 0 { vcp.info("invalid select no", ino, ipt);  exit(-1) }
    }

	if ino >= 0 && ino < rcvals.len {
			// parse line
			pkgline := rcvals[ino]
			hv, pkg, ver := parse_nixstore_line(pkgline)
			vcp.info(hv, pkg, ver)

		// mut nix := Nixbase.new() // (hosturl)
        // mut nix := Nixbase.new(nixst_tuna)
        // mut nix := Nixbase.new(nixst_sjtu)
        // mut nix := Nixbase.new(nixst_ustc)
        // mut nix := Nixbase.new(nixst_nju)
        mut nix := Nixbase.new(nixst_sustech)
		nix.stpath = pkgline

			stpurl := nix.storeurl() + pkgline
			vcp.info("store path full", stpurl)

		mut pker := Repacker.new(nix)
        defer { pker.cleanup() }
        vcp.info("downloading...", pkgline)
		pker.dl_store_path2() or {
			vcp.info(err.str())
			return
		}
        // vcp.info("detect_binarch...", pkgline)
		// arch := pker.detect_binarch() or {
		// 	vcp.error(err.str(), pkgline)
		// 	pker.cleanup()
		// 	exit(-1)
		// }
		// match arch {
		// 	'arm64' { vcp.warn("ok but ignore now:", arch)
		// 	pker.cleanup(); exit(-1)}
		// 	else{}
		// }

			pkgdir := "pkgs/${pkgline}"
			mydir := os.getenv("PWD")
			vcp.info(mydir, pkgdir)

			tmptar := "test123.tar"
			tmpgz := "${tmptar}.gz"

            assert pkgdir!=""

			// runcmd("tar zcf ${mydir}/${tmpgz} .", pkgdir, false)
			runcmd("tar cfp ${mydir}/${tmptar} .", pkgdir, false)
			srcinfo := genpkg_dot_srcinfo(pkg, ver, pkgline, os.file_size(tmptar))
			os.write_file("pkgs/.PKGINFO", srcinfo) !
			// defer {os.rm("pkgs/.PKGINFO")!}

			// repack so it prefixed with usr/local
			runcmd("mkdir pkgs/usr/local -p", "", false)
			runcmd("tar xf ${mydir}/${tmptar}", os.real_path("pkgs/usr/local"), false)
			runcmd("rm -f ${tmptar}", "", false)
			
			vcp.info("wkdir", os.getenv("PWD"))
			runcmd("sudo chmod 755 -R pkgs/usr", "", false)

        // uniform processes
        pctx := pker.process_files("pkgs/usr/local")
        if true {
            // pker.cleanup()
            // return
        }
        if pctx.skip {
            vcp.warn("skiped", pctx.reason)

            return
        }
			// resolve dlpath
			// replace_sharelib_ldpaths("pkgs/usr/local")
			// some clean share/man/info
			runcmd("sudo rm -rf pkgs/usr/local/share/man", "", false)
			runcmd("sudo rm -rf pkgs/usr/local/share/info", "", false)
			runcmd("sudo rm -f pkgs/usr/local/nix-support/propagated-user-env-packages", "", false)
			runcmd("sudo rm -f pkgs/usr/local/nix-support/setup-hook", "", false)

        if pker.narval.nar_size > 8*1000*1000 {
            vcp.info("compressing to", tmpgz, "about", pker.narval.nar_size)
        }

            os.cp(pker.narinfo_file, "pkgs/usr/local/${os.base(pkgline)}.narinfo") or { vcp.info(err.str()); return }
			runcmd("fakeroot -- tar zcfp ${mydir}/${tmpgz} usr/ .PKGINFO usr/local/${os.base(pkgline)}.narinfo", os.real_path( "pkgs/"), false)
			// runcmd("tar tf ${tmpgz}", "", false)
			runcmd("gzip -tv ${tmpgz}", "", false)
			runcmd("ls -lh ${tmpgz}", "", false)
			runcmd("mv ${tmpgz} ${pkg}-${ver}.darwin.amd64.pkg.tar.gz", "", false)
        // last check
        // runcmd("tar -zx -O -f ${pkg}-${ver}.darwin.amd64.pkg.tar.gz  .PKGINFO")

		// pker.cleanup()
		}
	// demo()
}

pub struct Repacker {
	pub mut:
	nb &Nixbase = vnil
	recursive bool
	stpath string // original
	narval Narinfo

    narinfo_file string
    narpkg_file string

	depends []&Repacker
	deriver &Repacker = vnil // must & or invalid recursive struct error
}

pub interface FileModer {
    // 返回值：
    // true, false 表示是否skip, early return
    // err, 表示有处理错误
    trymod(fm FileMeta) !bool
}

pub fn Repacker.new(nb &Nixbase) &Repacker {
	nb2 := refvar2mut(nb)
	assert nb.stpath != ""
	return &Repacker{nb:nb2, stpath:nb.stpath}
}

// todo continue interrupted download
pub fn (mut me Repacker) dl_store_path2() !int {
	vcp.info(me.stpath)
	hsval, pkg, ver := parse_nixstore_line(me.stpath)
	hsval2 := hsval.replace("/nix/store/", "")
	// vcp.info(hsval, pkg, ver, me.stpath)
    narinfo_file := "${me.nb.srcdir}/${hsval2}.narinfo"
    narpkg_file := "${me.nb.srcdir}/${os.base(me.stpath)}.nar.xz"
    me.narinfo_file = narinfo_file
    me.narpkg_file = narpkg_file

	// fetch .narinfo
    if !os.exists(narinfo_file) {
        url0 := me.nb.storeurl() + "${hsval2}.narinfo"
        // vcp.info(url0, me.stpath)

        mut ch := curlv.new()
        ch.url(url0).useragent("nix/2.21")
        mut res := ch.get()!
        // vcp.info(res.stcode, res.data, me.stpath)
        if res.stcode > 303 { return error("http resp ${res.stcode}")}
        os.write_file(narinfo_file, res.data) or {
            return err
        }

        ni := parse_narinfo(res.data)
        // vcp.info(ni.str())
        vcp.info("depends", ni.references)
        me.narval = ni
    }else{
        data := os.read_file(narinfo_file) or { return err }
        ni := parse_narinfo(data)
        // vcp.info(ni.str())
        vcp.info("depends", ni.references)
        me.narval = ni
    }
    ni := me.narval

    // fetch narpkg file
    if !os.exists(narpkg_file) {
        url1 := me.nb.storeurl() + "${ni.relative_url}"
        // vcp.info(url1)

        tmpnar := "pkgs/"+me.stpath.all_after_first("-") +".nar.xz"
        mut ch := curlv.new()
        ch.http1()
        ch.url(url1).useragent("nix/2.21")
        res := ch.get_tofile(tmpnar)!
        vcp.info(res.stcode, res.data, os.file_size(tmpnar),  me.stpath)
        // defer {os.rm(tmpnar)or{}}
        if res.stcode > 303 { return error("httpresp ${res.stcode}")}
        _, ok := runcmd("xz -tv ${tmpnar}", "", false)
        if !ok {
            return error("dlerr")
        }
        os.mv_by_cp(tmpnar, narpkg_file, os.MvParams{true}) or {
            vcp.error(err.str(), tmpnar)
            return err
        }
    }

	// runcmd("cat ${tmpnar}|nix-store --restore pkgs/nix/", "", false)
    // rm -rf 防止有未能清理的文件
	cmd := "mkdir -p pkgs/${me.stpath} && sudo rm -rf pkgs/${me.stpath} && cat ${narpkg_file}|xz -dc|nix-store --restore pkgs/${me.stpath}"
	os.write_file("pkgs/unnar.sh", cmd)!
	runcmd("sh pkgs/unnar.sh", "", false)
	if true {return 0}
	return error("testing...")
}

// pub fn pipe_file_toproc()

pub fn (me &Repacker) dl_store_path() !int {
	pkgline := me.stpath
	runcmd("nix copy ${pkgline} --to pkgs/ --impure --no-use-registries --no-update-lock-file --no-write-lock-file --no-recursive --refresh --repair -v --debug --keep-derivations", "", false)
	pkgdir := "pkgs/${pkgline}"
	dotsrcinfo := pkgdir + "/.PKGINFO"
	vcp.info("saved", os.exists(pkgdir), pkgdir)
	// exit(-1)
	if !os.exists(pkgdir){
		vcp.info("wtf 404", pkgdir)
		// exit(-1)
		return error_with_code("dl stpath error", -1)
	}
	return 0
}

// 查看包是否可用，1, 仅包含exescript, 2 不包含macx64之外的
pub fn (me &Repacker) process_files(dir string) &DirwalkContext {
    mut spctx := &DirwalkContext{}
    spctx.btime = time.now()
	// mut spctx := 0
	// os.walk_with_context(dir, voidptr(&spctx), fn (ctx voidptr, f string) {
    // it's hack version, see vcp
    vcp.walk_with_exit(dir, voidptr(spctx), fn(mut ctx DirwalkContext, f string) bool {
        if is_source_file_byext(f) { return true}
		if os.is_dir(f) || os.is_link(f) { return true}
        ctx.file_cnt+=1
        fm := get_file_meta(f)

        len0 := ctx.fmetas.len
        len1 := ctx.file_cnt
        ctx.prbar.step(len0, len1, "inwalk: ${len0}/${len1} ${os.base(f)} ${fm.str0()}")

        // vcp.info(len0, len1, "inwalk: ${len0}/${len1} ${os.base(f)} ${fm.str2()}")
        if fm.islnx { ctx.skip = true;
            ctx.reason = "islnx, ${fm.str2()}"
            return false }
        if fm.ismac && fm.isarm() { ctx.skip = true;
            ctx.reason = "mac.arm, ${fm.str2()}"
            return false }

        if fm.isexe() { ctx.fmetas << fm }
        if fm.isbinexe() {
            replace_sharelib_ldpath(f, len0, len1)
        }else if fm.isexescript {
            replace_exe_script_ldpath(f, len0, len1)
        } else {
            // vcp.info(f, fm.meta)
            // return true
        }
        
        return true
	})
    spctx.prbar.end()
	vcp.info("binarcherr", spctx.str().elide_right(88), time.since(spctx.btime).str(), spctx.skip, spctx.reason, dir)

    return spctx
}

pub type MapSI = map[string]int
pub type MapSS = map[string]string

const langsrcexts = [".txt", ".md", ".v", ".h", ".go", ".c", ".cpp", ".cxx", ".cc", ".el", ".s"]
// mainly for check binary executable
fn is_uncare_file(f string) bool {
    return os.is_dir(f) || os.is_link(f) || !os.is_executable(f)
}
fn is_source_file_byext(f string) bool {
    for ext in langsrcexts {
        if f.ends_with(ext) { return true }
    }
    return false
}
fn is_source_file(s string) bool {
    return s.ends_with("source text, ASCII text")
}
// python, bash,
// s: file:  path/to/file 的输出
fn is_exe_script(s string) bool {
    // Python      script text executable, ASCII text
    // POSIX shell script text executable, ASCII text
    // l := s.to_lower()
    return s.contains('script text executable, ASCII text')
}
// ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked
// ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked
fn is_linux_elf(s string) bool {
    l := s.to_lower().trim_space()
    return l.contains("elf") && l.contains("lsb")
}
// Mach-O 64-bit executable x86_64
// Mach-O 64-bit dynamically linked shared library x86_64
fn is_mac_obj(s string) bool {
    return s.contains("Mach-O") &&
        (s.contains("executable") || s.contains("shared library"))
}

fn get_file_cpuarch(s string) string {
    if is_mac_obj(s) { return s.all_after_last(" ")} 
    else if is_linux_elf(s) { return s.split(", ")[1].all_after(" ")}
    else if is_exe_script(s) { return "any"}
    return "cpu??"
}

// todo aarch64 cannot
// todo support return os
pub fn (me &Repacker) detect_binarch() !string {
	stpath := me.stpath
	pkgdir := "pkgs/${stpath}"

	mut archs := map[string]int{}
    mut osnames := map[string]int{}
	dir_walk_withctx(pkgdir, mut archs, fn(mut ctx map[string]int, f string){
		// vcp.info(f, os.is_executable(f))
        if os.is_dir(f) || os.is_link(f) { return }
		if !os.is_executable(f) { return }
		lines, _ := runcmdv("file ${f}")
		// vcp.info(f, lines.str())
		if lines.len>0 && lines[0].contains("Mach-O") && lines[0].contains("executable") {
			arch := lines[0].all_after_last(" ")
			ctx[arch] = 1+ ctx[arch]or{0}
		}
	})
	vcp.info(archs.len, archs.str(), pkgdir)

	mut arch := "any"
	if archs.len == 0 {
		// look good
	}else if archs["x86_64"]>0 && archs["arm64"]>0 {
		vcp.warn("complex", archs.str(), stpath)
		return error("cannot resolve pkgarch, ${archs.keys()}")
	} else if archs["x86_64"]>0 {
		// ok
		arch = archs.keys().first()
	} else {
		// vcp.error("not support", archs.str(), pkgline)
		arch = archs.keys().first()
	}

	return arch
}

pub fn (mut me Repacker) packit() {

}

pub fn (mut me Repacker) clean_unused() {

}

pub fn (mut me Repacker) cleanup() {
	vcp.info("pkgs/{usr,nix}", os.base(me.stpath))
	// runcmd("rm -rf pkgs/usr/local", "", false)
	runcmd("sudo rm -rf pkgs/usr/local", "", false)
	// runcmd("rm -rf pkgs/nix/store/", "", false)
	runcmd("sudo rm -rf pkgs/nix/store/", "", false)
	runcmd("sudo rm -rf pkgs/nix/var/", "", false)
}

fn get_cmds_full_paths(cmds ... string) map[string]string{
	return map[string]string{}
}

// /nix/store/w5v7c0ikm6mzf17f3zyjvf0cn8gcammm-xxx =>
// w5v7c0ikm6mzf17f3zyjvf0cn8gcammm.narinfo
// not need
fn store_path_to_narpath(stpath string) string {
	return stpath
}

fn cleanup_temps() {
}

pub fn dir_walk_withctx<T>(dir string, mut ctx T, fun fn (mut ctx T, f string)) {
	os.walk_with_context(dir, ctx, fun)
}

fn addassignop<T>(v T, p voidptr) T {
	mut n := unsafe { *(&T(p)) }
	n += v
	unsafe { *(&T(p)) = n }
	return n
}

fn replace_exe_script_paths(dir string) {

}

fn replace_sharelib_ldpaths(dir string) DirwalkContext {
    // replace_sharelib_ldpaths1(dir)
    return replace_sharelib_ldpaths2(dir)
}
fn replace_sharelib_ldpaths2(dir string) DirwalkContext {
    mut spctx := DirwalkContext{}
    spctx.btime = time.now()
	// mut spctx := 0
	// os.walk_with_context(dir, voidptr(&spctx), fn (ctx voidptr, f string) {
    dir_walk_withctx(dir, mut spctx, fn(mut ctx DirwalkContext, f string) {
        ctx.file_cnt+=1
		// vcp.info(f, os.is_dir(f), os.is_link(f))
		if os.is_dir(f) || os.is_link(f) { return }
        if !os.is_executable(f) { return }
		if !check_binarch(f) { // addassignop(1, ctx)
            ctx.arch_nerr+=1
			vcp.info(check_binarch(f), ctx.str(), f)
		}
        ctx.binfiles << f
        len0 := ctx.binfiles.len
        len1 := ctx.file_cnt
        ctx.prbar.step(len0, len1, "inwalk: ${len0}/${len1} ${os.base(f)}")
        // vcp.info(len0, len1, "inwalk: ${len0}/${len1} ${os.base(f)}")
		// replace_sharelib_ldpath(f, ctx.file_cnt)
	})
    spctx.prbar.end()
	vcp.info("binarcherr", spctx.str().elide_right(88), time.since(spctx.btime), dir)
    len1 := spctx.binfiles.len
    for idx, f in spctx.binfiles {
        spctx.prbar.step(idx, len1, "infor: ${idx}/${len1} ${os.base(f)}")
        replace_sharelib_ldpath(f, idx, len1)
        gc_collect()
    }
    spctx.prbar.end()
    if spctx.binfiles.len>99 { vcp.info("done", len1, dir)}
	vcp.falseprt(spctx.arch_nerr==0, "binarch not match", spctx.str(), time.since(spctx.btime).str(), dir)

    return spctx
}
    struct DirwalkContext {
        pub mut:
        arch_nerr int
        file_cnt int
        btime time.Time
        skip bool
        reason string
        binfiles []string
        fmetas []FileMeta
        prbar &vcp.TermPrbar = vcp.TermPrbar.new()
    }

struct FileMeta {
    pub mut:
    file string
    meta string
    islnx bool
    ismac bool
    isarm32 bool
    isarm64 bool
    isamd64 bool
    isx86 bool
    isexescript bool
}

// todo two slow when many bin/lib, such as emacs's 3000 .eln files
// todo generate bash script, and batch run
// bug? maybe this cause memory usage up to 7100M?
fn replace_sharelib_ldpaths1(dir string) DirwalkContext {
    mut spctx := DirwalkContext{}
    spctx.btime = time.now()
	// mut spctx := 0
	// os.walk_with_context(dir, voidptr(&spctx), fn (ctx voidptr, f string) {
    dir_walk_withctx(dir, mut spctx, fn(mut ctx DirwalkContext, f string) {
        ctx.file_cnt+=1
        if ctx.skip { return }
        if time.since(ctx.btime)>3*time.minute || ctx.file_cnt > 300 {
            if !vcp.term_askyn("used ${time.since(ctx.btime)}, files ${ctx.file_cnt}, continue?") {
                ctx.skip = true
                return
            }
        }
		// vcp.info(f, os.is_dir(f), os.is_link(f))
		if os.is_link(f) {
			// vcp.info(f, "=>", os.real_path(f))
		}
		if os.is_dir(f) || os.is_link(f) { return }
        if !os.is_executable(f) { return }
		if !check_binarch(f) { // addassignop(1, ctx)
            ctx.arch_nerr+=1
			vcp.info(check_binarch(f), ctx.str(), f)
            ctx.skip = true
            return
		}
		replace_sharelib_ldpath(f, ctx.file_cnt, 0)
	})
	// vcp.info("binarcherr", spctx, dir)
	vcp.falseprt(spctx.arch_nerr==0, "binarch not match", spctx.str(), time.since(spctx.btime).str(), dir)
    
    return spctx
}
fn replace_sharelib_ldpath(file string, idx int, tot int) {
	lines, ok := runcmdv("otool -L ${file}")
	// vcp.info(lines)
	if lines.len < 1 { return }
	if lines[0].contains("is not an object file") { return }

	mut changed := false
	for i:=1; i < lines.len;i++ {
		line := lines[i].trim_space()
		if !line.starts_with("/nix/store/") { continue }
        // 这一行日志输出导致了内存爆涨！！！7G以上。大概在有3000次循环的时候（emacs)
        // 没有这一行的话，大概内存保持在50M左右不变。
        // 有可能是获取调用栈的时候的问题？？？
		vcp.info(i.str(), "need resolve ldpath", line, idx, tot, file)

		libpath := line.all_before(" ")
		libbase := os.base(libpath)
		newpath := "@rpath/${libbase}"
		newpath2 := "/usr/local/lib/${libbase}"
		// install_name_tool -change
		runcmd("install_name_tool -change ${libpath} ${newpath} $file", "", false)
		changed = true
	}
	if changed {
		runcmd("otool -L ${file}", "", false)
	}
}

// assume is exe script file, no check
fn replace_exe_script_ldpath(file string, idx int, tot int) {
    pfx := "/nix/store"
    mut edited:= 0
    mut lines := os.read_lines(file) or {panic(err)}
    for i:=0;i <lines.len;i++ {
        mut s := lines[i]
        if s.len == 0 { continue }
        if !s.contains(pfx) {
            continue
        }
        edited ++
        // vcp.info("need replace", s, file)
        cnt := s.count(pfx)
        for j :=0; j < cnt && s.contains(pfx); j++ {
            pos0 := s.index(pfx) or {panic(err)}
            pos2 := s.index_after("/", pos0+pfx.len+1)
            t := s.substr(pos0, pos2)
            // vcp.info(t)
            s = s.replace(t, "/usr/local")
            shcmd := "/usr/local/bin/bash"
            if s.contains(shcmd) && !os.exists(shcmd) {
                s = s.replace(shcmd, "/bin/sh")
            }
            vcp.info(s, file)
        }
        lines[i] = s
    }
    if edited > 0 {
        scc := lines.join("\n")
        os.write_file(file, scc) or { 
            vcp.info(err.str(), file)
            // return
        }
        // runcmd("head ${file}", "", false)
        vcp.info(edited, file)
    }
}

// Mach-O 64-bit executable x86_64
fn check_binarch(file string) bool {
	lines, ok := runcmdv("file ${file}")
	filety := firstofv(lines)
    if is_mac_obj(filety) && get_file_cpuarch(filety) == "x86_64" { return true }
	// vcp.info(filety,  filety.contains("executable"), filety.contains("x86_64") )
	// if filety.contains("Mach-O") && filety.contains("executable") && !filety.contains("x86_64") {
	// 	return false
	// }
	// return true
    return false
}

fn get_file_meta(file string) FileMeta {
    mut fm := FileMeta{file:file}
    lines, ok := runcmdv("file ${file}")
    filety := firstofv(lines)
    // vcp.info(filety.len, file, filety)

    fm.meta = filety
    fm.islnx = is_linux_elf(filety)
    fm.ismac = is_mac_obj(filety)
    fm.isexescript = is_exe_script(filety)
    cputy := get_file_cpuarch(filety)
    fm.isamd64 = cputy == "x86-64" || cputy == "x86_64" || cputy == "arm64" 
    fm.isarm64 = cputy == "aarch64" || cputy == "arm64"

    // vcp.info(fm.str(), cputy)

    return fm
}
fn (fm FileMeta) isarm() bool { return fm.isarm64 || fm.isarm32 }
fn (fm FileMeta) isamd() bool { return fm.isx86 || fm.isamd64 }
fn (fm FileMeta) isexe() bool { return fm.islnx || fm.ismac || fm.isexescript }
fn (fm FileMeta) isbinexe() bool { return fm.islnx || fm.ismac }
fn (fm FileMeta) str0() string {
    ismac := fm.ismac.toc()
    isamd := fm.isamd().toc()
    isexe := fm.isexe().toc()
    return "mac:${ismac},x64:${isamd},exe:${isexe}"
}
fn (fm FileMeta) str2() string {
    mut osval := "wtos"
    mut arch := "wtcpu"
    if fm.islnx { osval = "linux"}
    else if fm.ismac { osval = "mac" }
    if fm.isarm64 { arch = "arm64"}
    else if fm.isarm32 { arch = "arm32"}
    else if fm.isamd64 { arch = "amd64"}
    else if fm.isx86 { arch = "x86" }

    return "osarch: ${osval}-${arch}, exe: ${fm.isexe()}"
}

// line: /nix/store/imhzscw3r1rd6x40ddc5wwknwdsz6x5r-par2cmdline-0.8.1
fn parse_nixstore_line(line string) (string, string, string) {
	hv := line.all_before("-")
	ver := line.all_after_last("-")	
	pkg := line.all_after("-").all_before_last("-")
	return hv, pkg, ver
}

fn genpkg_dot_srcinfo(pkgname string, pkgver string, hashval string, pkgsize i64) string {
	mut lines := []string{}
	lines, _ = runcmdv("pacman -V")
	pacmanver := lines[1]
	lines,_ = runcmdv("makepkg -V")
	makepkgver := lines[0]
	lines, _ = runcmdv("fakeroot -v")
	fakerootver := lines[0]
	builddate := time.now()

	s := "# Generated by makepkg 4.0.3
# ${pacmanver}
# ${makepkgver}
# ${fakerootver}
# using fakeroot version 1.31
# Wed Oct 23 14:41:09 UTC 2024
# ${builddate.str()}
pkgname = ${pkgname}
pkgver = ${pkgver}-1
pkgdesc = Gives a fake root environment
url = ${hashval}
# builddate = 1729694468
builddate = ${builddate.unix()}
packager = Unknown Packager <pacnix@pacnix.org>
size = ${pkgsize}
arch = x86_64
license = GPL/GPL3/MIT/MIT3
group = extras
makepkgopt = strip
makepkgopt = docs
makepkgopt = !libtool
makepkgopt = emptydirs
makepkgopt = zipman
makepkgopt = purge
makepkgopt = !upx"

	return s
}

fn get_match_store_paths(store_path_file string, kw string) []string{
	mode := 1 // 1 grep, 2 linebyline, 3 readfull
	return match mode {
		1 { get_match_store_paths_grep(store_path_file, kw)}
		2 { get_match_store_paths_linebyline(store_path_file, kw)}
		3 { get_match_store_paths_readfull(store_path_file, kw)}
		else {[]string{}}
	}
}

fn get_match_store_paths_linebyline(store_path_file string, kw string) []string{
	mut rcvals := []string{}
	// ("store-path-head200")! // about 11M
	mut fp := os.open(store_path_file) or {panic(err)}
	defer {fp.close()}
	
	mut buf := []u8{len:96}
	for i:=0; !fp.eof() ;i++ {
		rn := fp.read_bytes_with_newline(mut &buf) or {
		vcp.error(err.str()); break}
		line := buf[..rn].bytestr().trim_space_right()
		// vcp.info(i, line.len, line, kw)
		// vcp.info(i, rn, buf.len, line.len, line)
		if line.len>0 && line.contains(kw) && line != "" {
			vcp.info("got???", i.str(), line.len, line)
			rcvals << line
		}
	}

	return rcvals
}
fn get_match_store_paths_readfull(store_path_file string, kw string) []string{
	vcp.info("not impl")	
	return []string{}
}

fn get_match_store_paths_grep(store_path_file string, kw string) []string{
	if kw.trim_space().len == 0 { return []string{} }
	stfile := store_path_file
	lines, ok := vcp.runcmdv("grep -i ${kw} ${stfile}")
	return lines
}

fn demo() {
	nix := Nixbase{}

	mut ch := curlv.new()
	ch.url(nix.pkgurl()).useragent("nix/2.21")
	mut res := ch.get() or { panic(err) }
	vcp.info(res.stcode, res.data.len, ch.redirurl())

	ch.url(nix.storeurl())
	res = ch.get() or { panic(err) }
	vcp.info(res.stcode, res.data.len, ch.redirurl())
}