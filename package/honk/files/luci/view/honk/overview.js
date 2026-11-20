'use strict';
'require view';
'require fs';
'require ui';

/*
 * LuCI entry point for honk.
 *
 * The real dashboard is doona, served by honk-core on port 9527. It is a
 * separate origin from LuCI, so it cannot be embedded in an iframe (honk sends
 * X-Frame-Options and a Host/Origin allow-list). This page therefore only
 * reports the service state and opens the panel in a new tab.
 */

return view.extend({
	load: function () {
		return fs.exec('/usr/libexec/zn-m2-honk-status', []).then(function (res) {
			if (res.code !== 0)
				throw new Error('无法读取 Honk 服务状态');
			return res.stdout.trim().split(/\s+/);
		});
	},

	panelUrl: function () {
		var host = window.location.hostname;
		return 'http://' + host + ':9527/';
	},

	render: function (data) {
		var enabled = (data[0] === '1');
		var running = (data[1] === '1');
		var rssKb = parseInt(data[2], 10) || 0;
		var url = this.panelUrl();

		var stateRow = function (label, value, good) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, label),
				E('td', { 'class': 'td left' }, [
					E('span', { 'style': good ? 'color:#2e7d32;font-weight:bold' : 'color:#c62828;font-weight:bold' }, value)
				])
			]);
		};

		var action = function (verb, label) {
			return E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function () {
					return fs.exec('/etc/init.d/honk', [verb]).then(function (res) {
						if (res.code !== 0)
							throw new Error('Honk 服务操作未成功，请查看系统日志');
						window.location.reload();
					}).catch(function (err) {
						ui.addNotification(null, E('p', {}, err.message), 'error');
					});
				})
			}, label);
		};

		return E([
			E('h2', {}, 'Honk 代理'),
			E('div', { 'class': 'cbi-map-descr' },
				'本版本的透明代理由 honk 提供，控制面板是内嵌的 doona。' +
				'doona 是一个独立的 Web 应用，不在 LuCI 内，需要在新标签页打开。'),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '服务状态'),
				E('table', { 'class': 'table' }, [
					stateRow('开机自启', enabled ? '已启用' : '已停用', enabled),
					stateRow('当前状态', running ? '运行中' : '未运行', running),
					stateRow('内存占用', rssKb ? Math.round(rssKb / 1024) + ' MiB' : '—', rssKb > 0),
					stateRow('面板地址', url, true)
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '操作'),
				E('div', { 'class': 'cbi-page-actions' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function () { window.open(url, '_blank', 'noopener'); }
					}, '打开 doona 面板'),
					' ',
					enabled ? action('disable', '取消开机自启') : action('enable', '设置开机自启'),
					' ',
					running ? action('stop', '停止服务') : action('start', '启动服务')
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, '说明'),
				E('ul', {}, [
					E('li', {}, '首次打开 doona 需要创建管理员账号，账号保存在 /etc/honk/data/state/honk.db。'),
					E('li', {}, '代理节点、订阅与分流规则都在 doona 中配置，配置文件是 /etc/honk/config.dae。'),
					E('li', {}, '默认路由为全部直连：配置节点之前不会产生任何代理流量。'),
					E('li', {}, 'honk 仍处于 alpha 阶段，配置热重载时进程可能退出，procd 会在数秒内重新拉起。')
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
