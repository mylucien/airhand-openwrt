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
			_('中继服务器和网页控制台都跑在这台路由器上。被控电脑安装 Airhand 客户端，' +
			  '把中继地址指向本机（config.toml 里的 server），然后用浏览器打开本机端口即可控制。'));

		/* ---------------- 中继服务器 ---------------- */
		s = m.section(form.NamedSection, 'relay', 'airhand', _('中继服务器'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'listen', _('监听地址'),
			_('UDP 端口，默认 0.0.0.0:4433。被控电脑和网页控制台都连这个端口。'));
		o.placeholder = '0.0.0.0:4433';
		o.rmempty = false;

		o = s.option(form.Value, 'max_sessions', _('每台被控端最多会话数'),
			_('同一台被控电脑最多允许几个控制端同时连接。'));
		o.datatype = 'uinteger';
		o.placeholder = '4';

		o = s.option(form.Value, 'cert_names', _('证书 SAN'),
			_('自动生成证书时写入的域名或 IP，逗号分隔。客户端按指纹校验，这里通常不用改。'));
		o.placeholder = 'airhand,localhost';

		o = s.option(form.ListValue, 'log_level', _('日志级别'));
		o.value('error', 'error');
		o.value('warn', 'warn');
		o.value('info', 'info');
		o.value('debug', 'debug');
		o.default = 'info';

		o = s.option(form.Value, 'data_dir', _('数据目录'),
			_('证书和 SQLite 数据库（控制码绑定表）所在目录，必须可写并且能持久保存。'));
		o.placeholder = '/etc/airhand/relay';

		o = s.option(form.Button, '_airhand_fp', _('证书指纹'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return fs.exec('/usr/libexec/airhand/fingerprint.sh').then(function(res) {
				var text = (res.code === 0) ? res.stdout.trim()
					: (res.stderr || res.stdout || _('读取失败，先启动一次中继'));
				ui.showModal(_('中继证书指纹'), [
					E('p', {}, _('把它填进被控电脑 config.toml 的 server_fp；' +
					             '为空时客户端会在第一次连接时记住它（TOFU）。')),
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
			_('TCP 端口，默认 0.0.0.0:8080。同一个端口同时支持 HTTP 和 HTTPS；' +
			  '从别的电脑访问必须用 https://，否则浏览器拿不到 WebCodecs 硬解。'));
		o.placeholder = '0.0.0.0:8080';
		o.rmempty = false;

		o = s.option(form.Value, 'relay', _('中继地址'),
			_('网页控制台连接的中继，默认就是本机的中继。'));
		o.placeholder = '127.0.0.1:4433';

		o = s.option(form.Value, 'server_fp', _('中继证书指纹'),
			_('留空则第一次连接时记住中继证书（TOFU）。中继就在本机时影响不大，' +
			  '但如果中继将来换证书，留空会自动认新证书，反而更省事。'));
		o.placeholder = _('留空 = 首次连接时记住');
		o.rmempty = true;

		o = s.option(form.Value, 'name', _('显示名称'),
			_('被控电脑托盘里「谁在控制」显示的名字。'));
		o.placeholder = 'Airhand Web';

		o = s.option(form.Value, 'password', _('访问密码'),
			_('浏览器打开时会弹出登录框，用户名随意。留空表示任何人都能访问控制台（危险）。'));
		o.password = true;
		o.placeholder = _('建议设置');
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
			_('写进自签名证书的域名或 IP，逗号分隔。填你实际访问用的地址，' +
			  '浏览器至少不会报「名称不匹配」（自签名警告仍然会有）。'));
		o.placeholder = '192.168.1.1,airhand.lan';
		o.rmempty = true;

		o = s.option(form.Value, 'data_dir', _('数据目录'),
			_('证书、控制台身份（controller-key.txt）和中继信任记录所在目录。'));
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

		o = s.option(form.Button, '_airhand_wan_on', _('开放公网访问'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return runHelper('/usr/libexec/airhand/wan-expose.sh', [ 'on' ]);
		};

		o = s.option(form.Button, '_airhand_wan_off', _('关闭公网访问'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return runHelper('/usr/libexec/airhand/wan-expose.sh', [ 'off' ]);
		};

		return m.render();
	}
});
