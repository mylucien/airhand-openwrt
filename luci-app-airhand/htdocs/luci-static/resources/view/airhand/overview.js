'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

function runHelper(cmd, args, okText) {
	return fs.exec(cmd, args || []).then(function(res) {
		var text = (res.code === 0) ? (res.stdout || okText || '') : ('失败：' + (res.stderr || res.stdout || ('code ' + res.code)));
		ui.addNotification(null, E('p', { 'style': 'word-break:break-all' }, text.trim()),
			(res.code === 0) ? 'info' : 'danger');
	});
}

return view.extend({
	load: function() {
		return uci.load('airhand');
	},

	render: function() {
		var m, s, o, passwordOption;

		m = new form.Map('airhand',
			_('Airhand 远程桌面'),
			_('中继服务器与网页控制台均在本机运行。被控端安装 Airhand 客户端后，' +
			  '将其配置中的中继地址指向本机，即可通过浏览器访问本机端口进行控制。'));

		/* ---------------- 中继服务器 ---------------- */
		s = m.section(form.NamedSection, 'relay', 'airhand', _('中继服务器'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'listen', _('监听地址'),
			_('UDP 监听地址，默认 0.0.0.0:4433。被控端与网页控制台均连接此端口。'));
		o.placeholder = '0.0.0.0:4433';
		o.rmempty = false;

		o = s.option(form.Value, 'max_sessions', _('最大会话数'),
			_('单台被控端允许同时建立的最大会话数，默认 4。'));
		o.datatype = 'uinteger';
		o.placeholder = '4';

		o = s.option(form.Value, 'cert_names', _('证书 SAN'),
			_('自动签发证书时写入的域名或 IP，以逗号分隔。客户端以指纹方式校验，通常无需修改。'));
		o.placeholder = 'airhand,localhost';

		o = s.option(form.ListValue, 'log_level', _('日志级别'));
		o.value('error', 'error');
		o.value('warn', 'warn');
		o.value('info', 'info');
		o.value('debug', 'debug');
		o.default = 'info';

		o = s.option(form.Value, 'data_dir', _('数据目录'),
			_('存放 TLS 证书与 SQLite 数据库（控制码绑定表）的目录。须可写且能持久保留。'));
		o.placeholder = '/etc/airhand/relay';

		o = s.option(form.Button, '_airhand_fp', _('查看证书指纹'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return fs.exec('/usr/libexec/airhand/fingerprint.sh').then(function(res) {
				var text = (res.code === 0) ? res.stdout.trim()
					: (res.stderr || res.stdout || _('读取失败，请先启动中继服务'));
				ui.showModal(_('中继证书指纹'), [
					E('p', {}, _('请填入被控端 config.toml 的 server_fp。' +
					             '留空时，客户端将在首次连接时记录该指纹（TOFU）。')),
					E('p', { 'style': 'word-break:break-all;font-family:monospace' }, text),
					E('div', { 'class': 'right' },
						E('button', { 'class': 'btn', 'click': ui.hideModal }, _('关闭')))
				]);
			});
		};

		o = s.option(form.Button, '_airhand_restart_relay', _('重启中继'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return runHelper('/etc/init.d/airhand-server', [ 'restart' ], _('中继已重启'));
		};

		/* ---------------- 网页控制台 ---------------- */
		s = m.section(form.NamedSection, 'web', 'airhand', _('网页控制台'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'listen', _('监听地址'),
			_('TCP 监听地址，默认 0.0.0.0:8080。同一端口同时提供 HTTP 与 HTTPS；' +
			  '远程访问须使用 https://，否则浏览器无法启用 WebCodecs 硬件解码。'));
		o.placeholder = '0.0.0.0:8080';
		o.rmempty = false;

		o = s.option(form.Value, 'relay', _('中继地址'),
			_('网页控制台所连接的中继地址，默认为本机中继。'));
		o.placeholder = '127.0.0.1:4433';

		o = s.option(form.Value, 'server_fp', _('中继证书指纹'),
			_('留空时于首次连接记录中继证书（TOFU）。中继位于本机时影响有限；' +
			  '若中继更换证书，留空可免于手动更新。'));
		o.placeholder = _('留空则首次连接时记录');
		o.rmempty = true;

		o = s.option(form.Value, 'name', _('显示名称'),
			_('被控端托盘「当前控制方」中显示的名称。'));
		o.placeholder = 'Airhand Web';

		o = s.option(form.Value, 'password', _('访问密码'),
			_('设置后浏览器将弹出 HTTP 基本认证对话框，用户名任意。' +
			  '留空则不校验身份，任何可达者均可使用控制台。'));
		o.password = true;
		o.placeholder = _('留空则不校验');
		passwordOption = o;

		o = s.option(form.Button, '_airhand_genpw', _('生成密码'));
		o.inputstyle = 'action';
		o.onclick = function(ev, section_id) {
			var chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
			var buf = new Uint8Array(20), out = '', i, el, input;

			try {
				window.crypto.getRandomValues(buf);
			} catch (e) {
				return Promise.resolve();
			}
			for (i = 0; i < buf.length; i++)
				out += chars[buf[i] % chars.length];

			el = null;
			try { el = passwordOption.getUIElement(section_id); } catch (e) { el = null; }
			input = el ? el.querySelector('input') : null;
			if (input) {
				input.value = out;
				input.dispatchEvent(new Event('change'));
			} else {
				ui.addNotification(null, E('p', {}, out), 'info');
			}
			return Promise.resolve();
		};

		o = s.option(form.Value, 'cert_names', _('HTTPS 证书 SAN'),
			_('写入自签名证书的域名或 IP，以逗号分隔。建议与实际访问地址保持一致，' +
			  '以避免名称不匹配告警（自签名证书本身的告警仍会出现）。'));
		o.placeholder = '192.168.1.1,airhand.lan';
		o.rmempty = true;

		o = s.option(form.Value, 'data_dir', _('数据目录'),
			_('存放 HTTPS 证书、控制台身份（controller-key.txt）与中继信任记录的目录。'));
		o.placeholder = '/etc/airhand/web';

		o = s.option(form.ListValue, 'log_level', _('日志级别'));
		o.value('error', 'error');
		o.value('warn', 'warn');
		o.value('info', 'info');
		o.value('debug', 'debug');
		o.default = 'info';

		o = s.option(form.Button, '_airhand_restart_web', _('重启控制台'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return runHelper('/etc/init.d/airhand-web', [ 'restart' ], _('控制台已重启'));
		};

		return m.render();
	}
});
