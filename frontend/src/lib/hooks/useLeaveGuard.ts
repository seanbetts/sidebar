import { beforeNavigate, goto } from '$app/navigation';

type LeaveGuardOptions = {
  isDirty: () => boolean;
  getAllowNavigateOnce: () => boolean;
  getPendingHref: () => string | null;
  setPendingHref: (value: string | null) => void;
  setIsLeaveDialogOpen: (value: boolean) => void;
  setAllowNavigateOnce: (value: boolean) => void;
};

export function useLeaveGuard(options: LeaveGuardOptions) {
  beforeNavigate(({ cancel, to }) => {
    if (options.getAllowNavigateOnce()) {
      options.setAllowNavigateOnce(false);
      return;
    }
    if (options.isDirty()) {
      cancel();
      options.setPendingHref(to?.url?.href ?? null);
      options.setIsLeaveDialogOpen(true);
    }
  });

  const stayOnPage = () => {
    options.setIsLeaveDialogOpen(false);
    options.setPendingHref(null);
  };

  const confirmLeave = async () => {
    options.setIsLeaveDialogOpen(false);
    const pending = options.getPendingHref();
    if (!pending) return;
    options.setAllowNavigateOnce(true);
    await goto(pending);
    options.setPendingHref(null);
  };

  return { stayOnPage, confirmLeave };
}
