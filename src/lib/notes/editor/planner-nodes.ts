// Inline TipTap nodes for embedding a real To-do / Goal in a note or journal entry.
// Each node stores a denormalized snapshot (see planner-chip.ts) and its NodeView
// reflects live state from the injected `editor.storage.planner` bridge, writing
// changes back to the DB. Imperative DOM matches the codebase style (blocks.ts,
// DragHandle) — no Svelte NodeViews.
import { Node } from '@tiptap/core';
import type { Editor } from '@tiptap/core';
import {
	chipTitle,
	reconcileTodoChip,
	reconcileGoalChip,
	type TodoChipAttrs,
	type GoalChipAttrs
} from './planner-chip';
import { PRIORITY_LABELS, type Priority, type GoalStatus } from '$lib/planner/types';
import type { PlannerBridge } from '$lib/planner/bridge';

function planner(editor: Editor): PlannerBridge | undefined {
	return (editor.storage as unknown as Record<string, unknown>).planner as PlannerBridge | undefined;
}

// ---- shared popover -------------------------------------------------------
let activePopover: HTMLElement | null = null;
function closePopover() {
	activePopover?.remove();
	activePopover = null;
	document.removeEventListener('mousedown', onDocDown, true);
	document.removeEventListener('keydown', onDocKey, true);
}
function onDocDown(e: MouseEvent) {
	if (activePopover && !activePopover.contains(e.target as HTMLElement)) closePopover();
}
function onDocKey(e: KeyboardEvent) {
	if (e.key === 'Escape') closePopover();
}
function openPopover(anchor: HTMLElement, build: (pop: HTMLElement) => void) {
	closePopover();
	const pop = document.createElement('div');
	pop.className = 'chip-popover';
	build(pop);
	document.body.appendChild(pop);
	const r = anchor.getBoundingClientRect();
	pop.style.left = `${Math.min(r.left, window.innerWidth - 240)}px`;
	pop.style.top = `${Math.min(r.bottom + 6, window.innerHeight - 200)}px`;
	activePopover = pop;
	document.addEventListener('mousedown', onDocDown, true);
	document.addEventListener('keydown', onDocKey, true);
}
function row(label: string): HTMLElement {
	const el = document.createElement('div');
	el.className = 'chip-pop-row';
	const l = document.createElement('span');
	l.className = 'chip-pop-label';
	l.textContent = label;
	el.appendChild(l);
	return el;
}

// ---- To-do ----------------------------------------------------------------
export const TodoChip = Node.create({
	name: 'todoChip',
	group: 'inline',
	inline: true,
	atom: true,
	selectable: true,
	draggable: true,
	addAttributes() {
		return {
			todoId: { default: '' },
			title: { default: '' },
			done: { default: false },
			due: { default: null },
			priority: { default: 0 },
			removed: { default: false }
		};
	},
	parseHTML() {
		return [{ tag: 'span[data-todo-chip]' }];
	},
	renderHTML({ node }) {
		const a = node.attrs as unknown as TodoChipAttrs;
		return [
			'span',
			{ 'data-todo-chip': a.todoId, class: 'todo-chip', contenteditable: 'false' },
			`${a.done ? '☑' : '☐'} ${chipTitle(a)}`
		];
	},
	addNodeView() {
		return ({ editor, node, getPos }) => {
			const dom = document.createElement('span');
			dom.className = 'todo-chip';
			dom.contentEditable = 'false';
			const box = document.createElement('button');
			box.type = 'button';
			box.className = 'chip-box';
			const label = document.createElement('span');
			label.className = 'chip-label';
			const meta = document.createElement('span');
			meta.className = 'chip-meta';
			dom.append(box, label, meta);

			let attrs = node.attrs as unknown as TodoChipAttrs;
			const p = planner(editor);
			if (p) attrs = reconcileTodoChip(attrs, p.getTodo(attrs.todoId));

			function reflect(a: TodoChipAttrs) {
				dom.classList.toggle('is-done', a.done);
				dom.classList.toggle('is-removed', a.removed);
				box.textContent = a.done ? '☑' : '☐';
				label.textContent = chipTitle(a);
				const bits: string[] = [];
				if (a.due) bits.push(a.due);
				if (a.priority > 0) bits.push(PRIORITY_LABELS[a.priority as Priority]);
				if (a.removed) bits.push('removed');
				meta.textContent = bits.join(' · ');
			}
			function persist(next: TodoChipAttrs) {
				attrs = next;
				reflect(next);
				const pos = typeof getPos === 'function' ? getPos() : null;
				if (pos == null) return;
				editor.view.dispatch(editor.view.state.tr.setNodeMarkup(pos, undefined, { ...next }));
			}
			reflect(attrs);

			box.addEventListener('mousedown', (e) => {
				e.preventDefault();
				if (attrs.removed) return;
				const next = !attrs.done;
				persist({ ...attrs, done: next });
				planner(editor)
					?.toggleTodo(attrs.todoId, next)
					.catch(() => persist({ ...attrs, done: !next }));
			});
			label.addEventListener('mousedown', (e) => {
				e.preventDefault();
				if (attrs.removed) return;
				openTodoPopover(dom, attrs, (patch) => {
					const merged = { ...attrs, ...patch };
					persist(merged);
					planner(editor)?.updateTodo(attrs.todoId, {
						due_on: merged.due,
						priority: merged.priority
					});
				});
			});

			return {
				dom,
				update: (n) => {
					if (n.type.name !== 'todoChip') return false;
					attrs = n.attrs as unknown as TodoChipAttrs;
					reflect(attrs);
					return true;
				},
				stopEvent: () => true,
				ignoreMutation: () => true,
				destroy: () => closePopover()
			};
		};
	}
});

function openTodoPopover(
	anchor: HTMLElement,
	attrs: TodoChipAttrs,
	onChange: (patch: Partial<TodoChipAttrs>) => void
) {
	openPopover(anchor, (pop) => {
		const dueRow = row('Due');
		const date = document.createElement('input');
		date.type = 'date';
		date.className = 'chip-pop-input';
		date.value = attrs.due ?? '';
		date.addEventListener('change', () => onChange({ due: date.value || null }));
		dueRow.appendChild(date);

		const prioRow = row('Priority');
		const wrap = document.createElement('div');
		wrap.className = 'chip-pop-btns';
		([0, 1, 2, 3] as Priority[]).forEach((pr) => {
			const b = document.createElement('button');
			b.type = 'button';
			b.className = 'chip-pop-btn' + (attrs.priority === pr ? ' is-sel' : '');
			b.textContent = PRIORITY_LABELS[pr];
			b.addEventListener('mousedown', (e) => {
				e.preventDefault();
				onChange({ priority: pr });
				closePopover();
			});
			wrap.appendChild(b);
		});
		prioRow.appendChild(wrap);
		pop.append(dueRow, prioRow);
	});
}

// ---- Goal -----------------------------------------------------------------
const GOAL_STATUSES: GoalStatus[] = ['active', 'done', 'archived'];

export const GoalChip = Node.create({
	name: 'goalChip',
	group: 'inline',
	inline: true,
	atom: true,
	selectable: true,
	draggable: true,
	addAttributes() {
		return {
			goalId: { default: '' },
			title: { default: '' },
			status: { default: 'active' },
			targetDate: { default: null },
			removed: { default: false }
		};
	},
	parseHTML() {
		return [{ tag: 'span[data-goal-chip]' }];
	},
	renderHTML({ node }) {
		const a = node.attrs as unknown as GoalChipAttrs;
		return [
			'span',
			{ 'data-goal-chip': a.goalId, class: 'goal-chip', contenteditable: 'false' },
			`🎯 ${chipTitle(a)}`
		];
	},
	addNodeView() {
		return ({ editor, node, getPos }) => {
			const dom = document.createElement('span');
			dom.className = 'goal-chip';
			dom.contentEditable = 'false';
			const box = document.createElement('button');
			box.type = 'button';
			box.className = 'chip-box';
			const icon = document.createElement('span');
			icon.className = 'chip-goal-ic';
			icon.textContent = '🎯';
			const label = document.createElement('span');
			label.className = 'chip-label';
			const meta = document.createElement('span');
			meta.className = 'chip-meta';
			dom.append(box, icon, label, meta);

			let attrs = node.attrs as unknown as GoalChipAttrs;
			const p = planner(editor);
			if (p) attrs = reconcileGoalChip(attrs, p.getGoal(attrs.goalId));

			function reflect(a: GoalChipAttrs) {
				dom.classList.toggle('is-done', a.status === 'done');
				dom.classList.toggle('is-removed', a.removed);
				box.textContent = a.status === 'done' ? '☑' : '☐';
				label.textContent = chipTitle(a);
				const bits: string[] = [a.status];
				if (a.targetDate) bits.push(a.targetDate);
				if (a.removed) bits.push('removed');
				meta.textContent = bits.join(' · ');
			}
			function persist(next: GoalChipAttrs) {
				attrs = next;
				reflect(next);
				const pos = typeof getPos === 'function' ? getPos() : null;
				if (pos == null) return;
				editor.view.dispatch(editor.view.state.tr.setNodeMarkup(pos, undefined, { ...next }));
			}
			reflect(attrs);

			box.addEventListener('mousedown', (e) => {
				e.preventDefault();
				if (attrs.removed) return;
				const next: GoalStatus = attrs.status === 'done' ? 'active' : 'done';
				persist({ ...attrs, status: next });
				planner(editor)
					?.setGoalStatus(attrs.goalId, next)
					.catch(() => persist({ ...attrs, status: attrs.status }));
			});
			label.addEventListener('mousedown', (e) => {
				e.preventDefault();
				if (attrs.removed) return;
				openGoalPopover(dom, attrs, (patch) => {
					const merged = { ...attrs, ...patch };
					persist(merged);
					const bridge = planner(editor);
					if (patch.status) bridge?.setGoalStatus(attrs.goalId, patch.status);
					if ('targetDate' in patch) bridge?.updateGoal(attrs.goalId, { target_date: merged.targetDate });
				});
			});

			return {
				dom,
				update: (n) => {
					if (n.type.name !== 'goalChip') return false;
					attrs = n.attrs as unknown as GoalChipAttrs;
					reflect(attrs);
					return true;
				},
				stopEvent: () => true,
				ignoreMutation: () => true,
				destroy: () => closePopover()
			};
		};
	}
});

function openGoalPopover(
	anchor: HTMLElement,
	attrs: GoalChipAttrs,
	onChange: (patch: Partial<GoalChipAttrs>) => void
) {
	openPopover(anchor, (pop) => {
		const statusRow = row('Status');
		const wrap = document.createElement('div');
		wrap.className = 'chip-pop-btns';
		GOAL_STATUSES.forEach((st) => {
			const b = document.createElement('button');
			b.type = 'button';
			b.className = 'chip-pop-btn' + (attrs.status === st ? ' is-sel' : '');
			b.textContent = st;
			b.addEventListener('mousedown', (e) => {
				e.preventDefault();
				onChange({ status: st });
				closePopover();
			});
			wrap.appendChild(b);
		});
		statusRow.appendChild(wrap);

		const dateRow = row('Target');
		const date = document.createElement('input');
		date.type = 'date';
		date.className = 'chip-pop-input';
		date.value = attrs.targetDate ?? '';
		date.addEventListener('change', () => onChange({ targetDate: date.value || null }));
		dateRow.appendChild(date);
		pop.append(statusRow, dateRow);
	});
}
