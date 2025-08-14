// https://mihomo.party/docs/guide/override/javascript
// Define main function (script entry)
let entranceGP = "Proxies";
let otherGP = ["Proxies","🎯Direct"];
let directGP = "🎯Direct";

let localPrefix = "lo-";

let JPBGP = "LoB-JP", USBGP = "LoB-US", HKBGP = "LoB-HK";
let JPFB = "FaB-JP", USFB = "FaB-US", HKFB = "FaB-HK";

let RegionGroupArr = [{
  name: JPBGP,
  type: "load-balance",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/JP.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "Japan"
}, {
  name: USBGP,
  type: "load-balance",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/US.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "USA"
}, {
  name: HKBGP,
  type: "load-balance",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/HK.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "Hong Kong"
}, {
  name: JPFB,
  type: "fallback",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/JP.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "Japan"
}, {
  name: USFB,
  type: "fallback",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/US.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "USA"
}, {
  name: HKFB,
  type: "fallback",
  icon: "https://raw.githubusercontent.com/Orz-3/mini/refs/heads/master/Color/HK.png",
  testUrl: "http://www.gstatic.com/generate_204",
  filterCode: "Hong Kong"
}];

let ignoreGP=RegionGroupArr.map(e=>e.name);

/**
 * @param {ClashConfig} config
 */
function main(config) {
  
  config = createLocalListeners(config, 8440, "socks");
  config = replaceGP(config)
  config = configWithProfile(config);

  return config;
}

/**
 * 替换默认代理组 - 前置步骤
 * @param {ClashConfig} config
 * @returns {ClashConfig}
 */
function replaceGP(config){
  console.log("func: replaceGP");
  let proxies = config.proxies.map(/** @type {ProxyConfig} */ e => e.name)
  config["proxy-groups"].forEach(e=>{
    if (e.name == entranceGP) {
      e.proxies = [...proxies];
    }else if (e.name == directGP) {
      e.proxies = ["DIRECT", entranceGP];
    }else{
      e.proxies = [entranceGP, directGP, ...proxies];
    }
  })
  return config
}

/**
 *
 * @param {ClashConfig} config
 * @returns {ClashConfig}
 */
function configWithProfile(config){
  console.log("func: configWithProfile");
  config = createRegionGroup(config);
//   config = addTunnel(config);
  return config
}

/**
 * add tunnel group
 * @param {ClashConfig} config
 * @returns {ClashConfig}
 */
function addTunnel(config){
  console.log("func: addTunnel");
  return config
}

/**
 *
 * @param {ClashConfig} config
 * @param {String} name
 * @param {Number} pos
 * @param {String[]} [ignore=[]]
 * @returns {ClashConfig}
 */
function addProxy2Group(config, name, pos=otherGP.length, ignore=[]){
  // after filter the group will filtered, so will cause
  // missing group name
  config["proxy-groups"].filter(e=>!~ignore.indexOf(e.name))
    .forEach(/** @type {ProxyGroup} */ e => {
      // self node should be first
      let loLen = config.proxies.filter(e=>e.name.startsWith(localPrefix)).length;
      let loc = pos+loLen;
      if (e.name === entranceGP) {
        loc = loLen;
      }
      e.proxies.splice(loc,0,name);
    });
  return config;
}

/**
 *
 * @param {ClashConfig} config
 * @returns {ClashConfig}
 */
function createRegionGroup(config){
  let addedGroups = RegionGroupArr.map(e=>createProxyGroup(config, e.name, true, e))
  addedGroups.forEach(e=>addProxy2Group(config, e.name, otherGP.length, ignoreGP))  
  return config
}

/**
 *
 * @param {ClashConfig} config
 * @param {String} groupName
 * @param {Boolean} enableFilter
 * @param {Object} options
 * @param {String} options.filterCode
 * @param {String} options.type
 * @param {String} options.icon
 * @param {String} options.testUrl
 * @returns {ProxyGroup}
 */
function createProxyGroup(config, groupName, enableFilter = true, options = {filterCode: "", type: "select",icon:"",testUrl:"http://www.gstatic.com/generate_204"}){
  console.log(`func: createProxyGroup+${groupName}`)
  let filterCode = options.filterCode || groupName;
  let proxyGroup = {"name": groupName, type: options.type,
    proxies: config.proxies.filter(e=>{
      let check = enableFilter ? !!~e.name.toLowerCase().indexOf(filterCode.toLowerCase()) : true
      return check
    }).map(/** @type {ProxyConfig} */ e => e.name),
    icon: options.icon,
    url: options.testUrl
  }
  config["proxy-groups"].push(proxyGroup);
  return proxyGroup
}
/**
 *
 * @param {ClashConfig} config
 * @returns {ClashConfig}
 */
function createLocalListeners(config, port=8440, type="socks"){
  console.log(`func: createLocalListeners+${port}`)
  let isListenersExist = "listeners" in config;
  if (!isListenersExist) {
    /**
     * @type {ListenerConfig}
     */
    config.listeners = []
  }
  let name = `${type} ${port}`;

  createProxyGroup(config, name, false,)
  config.listeners.push(/** @type {Listener} */ {name: name, port: port, proxy: name, type: type, udp: true, listen: "0.0.0.0"})
  return config
}

//#region
/**
 * @typedef {Object} TrojanConfig
 * @property {string} name - 节点名称
 * @property {string} server - 服务器地址
 * @property {number} port - 服务器端口
 * @property {boolean} tfo - 是否启用 TCP Fast Open
 * @property {"trojan"} type - 节点类型
 * @property {string} password - 连接密码
 * @property {string} sni - SNI 主机名
 * @property {boolean} skip-cert-verify - 是否跳过证书验证
 * @property {boolean} udp - 是否启用 UDP
 * @property {Object} tunnels - 隧道配置
 */

/**
 * @typedef {Object} VlessRealityOpts
 * @property {string} public-key Reality 公钥
 * @property {string} short-id Reality 短 ID
 */

/**
 * @typedef {Object} SmuxBrutalOpts
 * @property {boolean} enabled 是否启用 TCP Brutal 拥塞控制算法
 * @property {number} [up] 上传带宽（Mbps）
 * @property {number} [down] 下载带宽（Mbps）
 */

/**
 * @typedef {Object} VlessSmux
 * @property {boolean} enabled 是否启用多路复用
 * @property {"smux"|"yamux"|"h2mux"} [protocol="h2mux"] 多路复用协议
 * @property {number} [max-connections] 最大连接数（与 max-streams 冲突）
 * @property {number} [min-streams] 在开新连接前的最小流数（与 max-streams 冲突）
 * @property {number} [max-streams] 在开新连接前的最大流数（与 max-connections 和 min-streams 冲突）
 * @property {boolean} [statistic] 是否在面板中显示底层连接
 * @property {boolean} [only-tcp] 是否仅允许 TCP（UDP 走节点默认 UDP 传输）
 * @property {boolean} [padding] 是否启用填充
 * @property {SmuxBrutalOpts} [brutal-opts] TCP Brutal 配置
 */

/**
 * @typedef {Object} VlessConfig
 * @property {string} name 代理名称
 * @property {"vless"} type 固定为 "vless"
 * @property {string} server 服务器地址
 * @property {number} port 服务器端口
 * @property {boolean} [udp] 是否启用 UDP
 * @property {string} uuid 用户 UUID
 * @property {string} [flow] 流控方式
 * @property {string} [packet-encoding] 数据包编码方式
 *
 * @property {boolean} [tls] 是否启用 TLS
 * @property {string} [servername] TLS SNI
 * @property {string[]} [alpn] ALPN 列表
 * @property {string} [fingerprint] TLS 指纹
 * @property {string} [client-fingerprint] 客户端指纹
 * @property {boolean} [skip-cert-verify] 跳过证书验证
 * @property {VlessRealityOpts} [reality-opts] Reality 配置
 *
 * @property {"tcp"|"ws"|"grpc"|"h2"} network 网络类型
 * @property {VlessSmux} [smux] smux 配置
 */
//#endregion
/**
 * @typedef {Object} ClashConfig
 * @property {number} port 端口号
 * @property {number} socksPort SOCKS 端口号
 * @property {boolean} allowLan 是否允许局域网访问
 * @property {string} mode 工作模式
 * @property {string} logLevel 日志等级
 * @property {string} externalController 外部控制地址
 * @property {boolean} unifiedDelay 是否启用统一延迟
 * @property {Object} sniffer 嗅探配置
 * @property {Object} dns DNS 配置
 * @property {Object[]} proxies 节点列表
 * @property {Object[]} proxy-groups 节点分组
 * @property {string[]} rules 规则列表
 * @property {Object} profile 配置文件信息
 * @property {ListenerConfig?} listeners 监听配置
 * @property {Object[]} proxy-providers 外部节点提供商
 * @property {Object[]} rules-providers 外部规则提供商
 */
/**
 * @typedef {Object} ProxyGroup
 * @property {string} name 分组名称
 * @property {string} [icon] 分组图标（URL 或路径，可选）
 * @property {string} [url] 测速/检测用地址（部分类型需要）
 * @property {"select"|"url-test"|"fallback"|"load-balance"} type 分组类型
 * @property {string[]} proxies 节点名称列表
 * @property {number} [interval] 测速/检测间隔（秒，可选）
 * @property {boolean} [lazy] 是否延迟选择节点（load-balance 可选）
 * @property {"round-robin"|"consistent-hashing"|"sticky-sessions"} [strategy] 负载均衡策略
 */
/**
 * @typedef {Object} ShadowsocksConfig
 * @property {string} name 节点名称
 * @property {"ss"} type 节点类型（Shadowsocks 固定为 "ss"）
 * @property {string} server 服务器地址
 * @property {number} port 服务器端口
 * @property {string} cipher 加密方式
 * @property {string} password 密码
 * @property {boolean} udp 是否启用 UDP
 * @property {boolean} tfo 是否启用 TCP Fast Open
 */
/**
 * @typedef {string | Tunnel} TunnelEntry
 *  - 如果是 string：短格式，如 "tcp/udp,127.0.0.1:6553,114.114.114.114:53,proxy"
 *  - 如果是 Tunnel 对象：长格式
 */
/**
 * @typedef {Object} Tunnel
 * @property {("tcp"|"udp")[]} network 协议类型数组
 * @property {string} address 本地监听地址（IP:端口）
 * @property {string} target 目标地址（IP:端口 或 域名）
 * @property {string} proxy 使用的代理名称
 */
/**
 * @typedef {Object} TunnelConfig
 * @property {TunnelEntry[]} tunnels 隧道列表
 */

//#region listeners
/**
 * @typedef {Object} ShadowsocksListener
 * @property {string} name 监听器名称
 * @property {"shadowsocks"} type 固定为 "shadowsocks"
 * @property {number} port 监听端口
 * @property {string} listen 监听地址
 * @property {string} rule 使用的规则名
 * @property {string} proxy 关联的代理名称
 */

/**
 * @typedef {Object} VlessUser
 * @property {string} username 用户名
 * @property {string} uuid 用户 UUID
 * @property {string} [flow] 流控方式（例如 "xtls-rprx-vision"）
 */

/**
 * @typedef {Object} VlessRealityConfig
 * @property {string} dest Reality 目标地址（域名:端口）
 * @property {string} privateKey Reality 私钥
 * @property {string[]} shortId Reality 短 ID 列表
 * @property {string[]} serverNames 服务器域名列表
 */

/**
 * @typedef {Object} VlessListener
 * @property {string} name 监听器名称
 * @property {"vless"} type 固定为 "vless"
 * @property {string|number} port 监听端口或端口范围（支持 "200,302" 或 "401-429" 等格式）
 * @property {string} listen 监听地址
 * @property {string} [rule] 使用的规则名（可选）
 * @property {string} [proxy] 直接交由的代理名（可选）
 * @property {VlessUser[]} users 用户列表
 * @property {string} [wsPath] WebSocket 路径（可选）
 * @property {string} [grpcServiceName] gRPC 服务名（可选）
 * @property {string} [certificate] TLS 证书路径（可选，与 Reality 互斥）
 * @property {string} [privateKey] TLS 私钥路径（可选，与 Reality 互斥）
 * @property {VlessRealityConfig} [realityConfig] Reality 配置（可选，与 TLS 互斥）
 */
//#endregion
/**
 * @typedef {Object} ListenerConfig
 * @property {Array<ShadowsocksListener|VlessListener>} listeners 监听器列表
 */